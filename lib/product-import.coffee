debug = require('debug')('sphere-product-import')
_ = require 'underscore'
_.mixin require 'underscore-mixins'
Promise = require 'bluebird'
slugify = require 'underscore.string/slugify'
{SphereClient, ProductSync} = require 'sphere-node-sdk'

class ProductImport

  constructor: (@logger, options = {}) ->
    @sync = new ProductSync
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
        Promise.resolve()
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
          synced = @sync.buildActions(preparedProduct, existingProduct)
          if synced.shouldUpdate()
            @client.products.byId(synced.getUpdateId()).update(synced.getUpdatePayload())
          else
            Promise.resolve statusCode: 304
      else
        @_prepareNewProduct(prodToProcess).then (product) => @client.products.create(product)

    debug 'About to send %s requests', _.size(posts)
    Promise.all(posts)

  _ensureVariantDefaults: (variant) ->
    variantDefaults =
      attributes: []
      prices: []
      images: []

    _.defaults(variant, variantDefaults)

  _ensureDefaults: (product) =>
    debug 'ensuring default fields in variants.'
    if product.masterVariant
      product.masterVariant = @_ensureVariantDefaults(product.masterVariant)
    if product.variants
      product.variants = _.map product.variants, (variant) => @_ensureVariantDefaults(variant)
    return product

  _prepareUpdateProduct: (productToProcess, existingProduct) ->
    Promise.all [
      @_resolveProductCategories(productToProcess.categories)
      @_resolveReference(@client.taxCategories, 'taxCategory', productToProcess.taxCategory, "name=\"#{productToProcess.taxCategory?.id}\"")
    ]
    .spread (prodCatsIds, taxCatId) =>
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
      productToProcess = @_ensureDefaults(productToProcess)
      Promise.resolve productToProcess

  _prepareNewProduct: (product) ->
    Promise.all [
      @_resolveReference(@client.productTypes, 'productType', product.productType, "name=\"#{product.productType?.id}\"")
      @_resolveProductCategories(product.categories)
      @_resolveReference(@client.taxCategories, 'taxCategory', product.taxCategory, "name=\"#{product.taxCategory?.id}\"")
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
      else if @_cache[refKey][ref.id]
        resolve(@_cache[refKey][ref.id])
      else
        service.where(predicate).fetch()
        .then (result) =>
          if result.body.count is 0
            reject "Didn't found any match while resolving #{refKey} (#{predicate})"
          else
            # Todo: Handle multiple response, currently taking first response.
            @_cache[refKey][ref.id] = result.body.results[0].id
            resolve(result.body.results[0].id)

module.exports = ProductImport
