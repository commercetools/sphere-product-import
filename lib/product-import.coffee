debug = require('debug')('sphere-product-import')
_ = require 'underscore'
_.mixin require 'underscore-mixins'
Promise = require 'bluebird'
slugify = require 'underscore.string/slugify'
{SphereClient, ProductSync} = require 'sphere-node-sdk'

class ProductImport

  constructor: (@logger, options = {}) ->
    @sync = new ProductSync
    @sync.config [{type: 'prices', group: 'black'}].concat(['base', 'references', 'attributes', 'images', 'variants', 'metaAttributes'].map (type) -> {type, group: 'white'})
    @client = new SphereClient options
    @_resetCache()
    @_resetSummary()

  _resetCache: ->
    @_cache =
      productType: {}
      categories: {}
      taxCategory: {}

  _resetSummary: ->
    @_summary =
      emptySKU: 0
      created: 0
      updated: 0

  summaryReport: (filename) ->
    if @_summary.created is 0 and @_summary.updated is 0
      message = 'Summary: nothing to do, everything is fine'
    else
      message = "Summary: there were #{@_summary.created + @_summary.updated} imported products " +
        "(#{@_summary.created} were new and #{@_summary.updated} were updates)"

    if @_summary.emptySKU > 0
      message += "\nFound #{@_summary.emptySKU} empty SKUs from file input"
      message += " '#{filename}'" if filename

    message

  performStream: (chunk, cb) ->
    @_processBatches(chunk).then -> cb()
    .catch (err) -> cb(err.body)

  _processBatches: (products) ->
    batchedList = _.batchList(products, 30) # max parallel elem to process
    Promise.map batchedList, (productsToProcess) =>
      # extract all skus from master variant and variants of all jsons in the batch
      skus = @_extractUniqueSkus(productsToProcess)
      predicate = @_createProductFetchBySkuQueryPredicate(skus)
      # Check predicate size by: Buffer.byteLength(predicate,'utf-8')
      # Todo: Handle predicate if predicate size > 8kb
      # Fetch products from product projections end point by list of skus.
      @client.productProjections
      .where(predicate)
      .staged(true)
      .all()
      .fetch()
      .then (results) =>
        debug 'Fetched products: %j', results
        queriedEntries = results.body.results
        @_createOrUpdate productsToProcess, queriedEntries
      .then (results) =>
        _.each results, (r) =>
          switch r.statusCode
            when 201 then @_summary.created++
            when 200 then @_summary.updated++
        Promise.resolve(@_summary)
    ,{concurrency: 1} # run 1 batch at a time


  _createProductFetchBySkuQueryPredicate: (skus) ->
    skuString = "sku in (\"#{skus.join('", "')}\")"
    return "masterVariant(#{skuString}) or variants(#{skuString})"

  _extractUniqueSkus: (products) ->
    skus = []
    for product in products
      if product.masterVariant?.sku
        skus.push(product.masterVariant.sku)
      else @_summary.emptySKU++
      if product.variants and not _.isEmpty(product.variants)
        for variant in product.variants
          if variant.sku
            skus.push(variant.sku)
          else @_summary.emptySKU++
    return _.uniq(skus,false)


  _isExistingEntry: (prodToProcess, existingProducts) ->
    prodToProcessSkus = @_extractUniqueSkus([prodToProcess])
    _.find existingProducts, (existingEntry) =>
      existingProductSkus =  @_extractUniqueSkus([existingEntry])
      matchingSkus = _.intersection(prodToProcessSkus,existingProductSkus)
      if matchingSkus.length > 0
        true
      else
        false

  _createOrUpdate: (productsToProcess, existingProducts) ->
    debug 'Products to process: %j', {toProcess: productsToProcess, existing: existingProducts}

    posts = _.map productsToProcess, (prodToProcess) =>
      existingProduct = @_isExistingEntry(prodToProcess, existingProducts)
      if existingProduct?
        @_prepareUpdateProduct(prodToProcess, existingProduct).then (preparedProduct) =>
          console.log "updating product: #{prodToProcess.name.en}"
          synced = @sync.buildActions(preparedProduct, existingProduct)
          if synced.shouldUpdate()
            @client.products.byId(synced.getUpdateId()).update(synced.getUpdatePayload())
          else
            console.log "--->> nothing to update for product: #{prodToProcess.name.en} --->>"
            Promise.resolve statusCode: 304
      else
        @_prepareNewProduct(prodToProcess).then (product) => @client.products.create(product)

    debug 'About to send %s requests', _.size(posts)
    Promise.all(posts)

  _ensureVariantDefaults: (variant = {}) ->
    variantDefaults =
      attributes: []
      prices: []
      images: []

    _.defaults(variant, variantDefaults)

  _ensureDefaults: (product) =>
    debug 'ensuring default fields in variants.'
    _.defaults product,
      masterVariant: @_ensureVariantDefaults(product.masterVariant)
      variants: _.map product.variants, (variant) => @_ensureVariantDefaults(variant)
    return product

  _prepareUpdateProduct: (productToProcess, existingProduct) ->
    productToProcess = @_ensureDefaults(productToProcess)
    Promise.all [
      @_resolveProductCategories(productToProcess.categories)
      @_resolveReference(@client.taxCategories, 'taxCategory', productToProcess.taxCategory, "name=\"#{productToProcess.taxCategory?.id}\"")
      @_fetchAndResolveCustomReferences(productToProcess)
    ]
    .spread (prodCatsIds, taxCatId) ->
      if taxCatId
        productToProcess.taxCategory =
          id: taxCatId
          typeId: 'tax-category'
      if prodCatsIds
        productToProcess.categories = _.map prodCatsIds, (catId) ->
          id: catId
          typeId: 'category'
      if not productToProcess.slug
        debug 'slug missing in product to process, assigning same as existing product: %s', existingProduct.slug
        productToProcess.slug = existingProduct.slug # to prevent removing slug from existing product.
      Promise.resolve productToProcess

  _prepareNewProduct: (product) ->
    product = @_ensureDefaults(product)
    Promise.all [
      @_resolveReference(@client.productTypes, 'productType', product.productType, "name=\"#{product.productType?.id}\"")
      @_resolveProductCategories(product.categories)
      @_resolveReference(@client.taxCategories, 'taxCategory', product.taxCategory, "name=\"#{product.taxCategory?.id}\"")
      @_fetchAndResolveCustomReferences(product)
    ]
    .spread (prodTypeId, prodCatsIds, taxCatId) =>
      if prodTypeId
        product.productType =
          id: prodTypeId
          typeId: 'product-type'
      if taxCatId
        product.taxCategory =
          id: taxCatId
          typeId: 'tax-category'
      if prodCatsIds
        product.categories = _.map prodCatsIds, (catId) ->
          id: catId
          typeId: 'category'
      if not product.slug
        if not product.name
          Promise.reject 'Product name is required.'
        product.slug = @_generateSlug product.name
      Promise.resolve product


  _generateSlug: (name) ->
    slugs = _.mapObject name, (val) =>
      uniqueToken = @_generateUniqueToken()
      return slugify(val).concat("-#{uniqueToken}").substring(0, 256)
    return slugs

  _generateUniqueToken: ->
    _.uniqueId "#{new Date().getTime()}"

  _fetchAndResolveCustomReferences: (product) =>
    Promise.all [
      @_fetchAndResolveCustomReferencesByVariant(product.masterVariant),
      Promise.map product.variants, (variant) =>
        @_fetchAndResolveCustomReferencesByVariant(variant)
      ,{concurrency: 5}
    ]
    .spread (masterVariant, variants) ->
      Promise.resolve _.extend(product, { masterVariant, variants })

  _fetchAndResolveCustomReferencesByVariant: (variant) ->
    if variant.attributes and not _.isEmpty(variant.attributes)
      Promise.map variant.attributes, (attribute) =>
        if attribute and _.isArray(attribute.value)
          # TODO: check that it works!
          if _.every(attribute.value, @_isReferenceTypeAttribute)
            @_resolveCustomReferenceSet(attribute.value)
            .then (result) ->
              attribute.value = result
              Promise.resolve(attribute)
          else Promise.resolve(attribute)
        else
          if attribute and @_isReferenceTypeAttribute(attribute)
            @_resolveCustomReference(attribute)
            .then (refId) ->
              Promise.resolve
                name: attribute.name
                value:
                  id: refId
                  typeId: attribute.type.referenceTypeId
          else Promise.resolve(attribute)
      .then (attributes) ->
        Promise.resolve _.extend(variant, { attributes })
    else
      Promise.resolve(variant)


  _resolveCustomReferenceSet: (attributeValue) ->
    Promise.map attributeValue, (referenceObject) =>
      @_resolveCustomReference(referenceObject)


  _isReferenceTypeAttribute: (attribute) ->
    _.has(attribute, 'type') and attribute.type.name is 'reference'


  _resolveCustomReference: (referenceObject) ->
    service = switch referenceObject.type.referenceTypeId
      when 'product' then @client.productProjections
      # TODO: map also other references
    refKey = referenceObject.type.referenceTypeId
    ref = _.deepClone referenceObject
    ref.id = referenceObject.value
    predicate = referenceObject._custom.predicate
    @_resolveReference service, refKey, ref, predicate


  _resolveProductCategories: (cats) ->
    new Promise (resolve) =>
      if _.isEmpty(cats)
        resolve()
      else
        Promise.all cats.map (cat) =>
          @_resolveReference(@client.categories, 'categories', cat, "externalId=\"#{cat.id}\"")
        .then (result) -> resolve(result.filter (c) -> c)

  _resolveReference: (service, refKey, ref, predicate) ->
    new Promise (resolve, reject) =>
      if not ref
        resolve()
      if not @_cache[refKey]
        @_cache[refKey] = {}
      if @_cache[refKey][ref.id]
        resolve(@_cache[refKey][ref.id])
      else
        request = service.where(predicate)
        if refKey is 'product'
          request.staged(true)
        request.fetch()
        .then (result) =>
          if result.body.count is 0
            reject "Didn't find any match while resolving #{refKey} (#{predicate})"
          else
            if _.size(result.body.results) > 1
              @logger.warn "Found more than 1 #{refKey} for #{ref.id}"
            @_cache[refKey][ref.id] = result.body.results[0].id
            resolve(result.body.results[0].id)

module.exports = ProductImport
