debug = require('debug')('sphere-product-import')
_ = require 'underscore'
_.mixin require 'underscore-mixins'
Promise = require 'bluebird'
slugify = require 'underscore.string/slugify'
{SphereClient, ProductSync} = require 'sphere-node-sdk'
fs = require 'fs-extra'
path = require 'path'
EnumValidator = require './enum-validator'
UnknownAttributesFilter = require './unknown-attributes-filter'
CommonUtils = require './common-utils'
EnsureDefaultAttributes = require './ensure-default-attributes'

class ProductImport

  constructor: (@logger, options = {}) ->
    @sync = new ProductSync
    if options.blackList and ProductSync.actionGroups
      @sync.config @_configureSync(options.blackList)
    @ensureEnums = options.ensureEnums or false
    @filterUnknownAttributes = options.filterUnknownAttributes or false
    @ignoreSlugUpdates = options.ignoreSlugUpdates or false
    @batchSize = options.batchSize or 30
    @client = new SphereClient options.clientConfig
    @enumValidator = new EnumValidator @logger
    @unknownAttributesFilter = new UnknownAttributesFilter @logger
    @commonUtils = new CommonUtils @logger
    if options.defaultAttributes
      @defaultAttributesService = new EnsureDefaultAttributes @logger, options.defaultAttributes
    @_configErrorHandling(options)
    @_resetCache()
    @_resetSummary()
    debug "Product Importer initialized with config -> errorDir: #{@errorDir}, errorLimit: #{@errorLimit}, blacklist actions: #{options.blackList}, ensureEnums: #{@ensureEnums}"

  _configureSync: (blackList) =>
    @_validateSyncConfig(blackList)
    debug "Product sync config validated"
    _.difference(ProductSync.actionGroups, blackList)
      .map (type) -> {type: type, group: 'white'}
      .concat(blackList.map (type) -> {type: type, group: 'black'})

  _validateSyncConfig: (blackList) ->
    for actionGroup in blackList
      if not _.contains(ProductSync.actionGroups, actionGroup)
        throw ("invalid product sync action group: #{actionGroup}")

  _configErrorHandling: (options) =>
    if options.errorDir
      @errorDir = options.errorDir
    else
      @errorDir = path.join(__dirname,'../errors')
    fs.emptyDirSync(@errorDir)
    if options.errorLimit
      @errorLimit = options.errorLimit
    else
      @errorLimit = 30

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
      failed: 0
      productTypeUpdated: 0
      errorDir: @errorDir
    if @filterUnknownAttributes then @_summary.unknownAttributeNames = []

  summaryReport: (filename) ->
    if @_summary.created is 0 and @_summary.updated is 0 and @_summary.failed is 0
      message = 'Summary: nothing to do, everything is fine'
    else
      message = "Summary: there were #{@_summary.created + @_summary.updated} imported products " +
        "(#{@_summary.created} were new and #{@_summary.updated} were updates)"

    if @_summary.emptySKU > 0
      message += "\nFound #{@_summary.emptySKU} empty SKUs from file input"
      message += " '#{filename}'" if filename

    if @_summary.failed > 0
      message += "\n #{@_summary.failed} product imports failed. Error reports stored at: #{@errorDir}"

    report = {
      reportMessage: message
      detailedSummary: @_summary
    }
    report

  performStream: (chunk, cb) ->
    @_processBatches(chunk).then -> cb()

  _processBatches: (products) ->
    batchedList = _.batchList(products, @batchSize) # max parallel elem to process
    Promise.map batchedList, (productsToProcess) =>
      debug 'Ensuring existence of product type in memory.'
      @_ensureProductTypesInMemory(productsToProcess)
      .then =>
        if @ensureEnums
          debug 'Ensuring existence of enum keys in product type.'
          enumUpdateActions = @_validateEnums(productsToProcess)
          uniqueEnumUpdateActions = @_filterUniqueUpdateActions(enumUpdateActions)
          @_updateProductType(uniqueEnumUpdateActions)
      .then =>
        if @defaultAttributesService
          debug 'Ensuring default attributes'
          @_ensureDefaultAttributesInProducts(productsToProcess)
      .then =>
        skus = @_extractUniqueSkus(productsToProcess)
        predicate = @_createProductFetchBySkuQueryPredicate(skus)
        if Buffer.byteLength(predicate,'utf-8') > 7800
          errMessage = "product fetch query size: #{Buffer.byteLength(predicate,'utf-8')} bytes, exceeded the supported " +
            "size, please try with a smaller batch size."
          @logger.error(errMessage)
          throw (errMessage)
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
          @_handleProcessResponse(r)
        Promise.resolve(@_summary)
    , {concurrency: 1} # run 1 batch at a time

  _handleProcessResponse: (r) =>
    if r.isFulfilled()
      @_handleFulfilledResponse(r)
    else if r.isRejected()
      @_summary.failed++
      if @_summary.failed < @errorLimit or @errorLimit is 0
        if r.reason().message
          @logger.error(
            r.reason(),
            "Skipping product due to error message: #{r.reason().message}"
          )
        else
          @logger.error(
            r.reason(),
            "Skipping product due to error reason: #{r.reason()}"
          )
        if @errorDir
          errorFile = path.join(@errorDir, "error-#{@_summary.failed}.json")
          fs.outputJsonSync(errorFile, r.reason(), {spaces: 2})
      else
        @logger.warn "
          Error not logged as error limit of #{@errorLimit} has reached.
        "

  _handleFulfilledResponse: (r) =>
    switch r.value().statusCode
      when 201 then @_summary.created++
      when 200 then @_summary.updated++

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

    posts = _.map productsToProcess, (product) =>
      @_filterAttributes(product)
      .then (prodToProcess) =>
        existingProduct = @_isExistingEntry(prodToProcess, existingProducts)
        if existingProduct?
          @_fetchSameForAllAttributesOfProductType(prodToProcess.productType)
          .then (sameForAllAttributes) =>
            @_prepareUpdateProduct(prodToProcess, existingProduct).then (preparedProduct) =>
              synced = @sync.buildActions(preparedProduct, existingProduct, sameForAllAttributes)
              if synced.shouldUpdate()
                @client.products.byId(synced.getUpdateId()).update(synced.getUpdatePayload())
              else
                Promise.resolve statusCode: 304
        else
          @_prepareNewProduct(prodToProcess)
          .then (product) =>
            @client.products.create(product)

    debug 'About to send %s requests', _.size(posts)
    Promise.settle(posts)

  _filterAttributes: (product) =>
    new Promise (resolve) =>
      if @filterUnknownAttributes
        @unknownAttributesFilter.filter(@_cache.productType[product.productType.id],product, @_summary.unknownAttributeNames)
        .then (filteredProduct) ->
          resolve(filteredProduct)
      else
        resolve(product)


  # updateActions are of the form:
  # { productTypeId: [{updateAction},{updateAction},...],
  #   productTypeId: [{updateAction},{updateAction},...]
  # }
  _filterUniqueUpdateActions: (updateActions) =>
    _.reduce _.keys(updateActions), (acc, productTypeId) =>
      actions = updateActions[productTypeId]
      uniqueActions = @commonUtils.uniqueObjectFilter actions
      acc[productTypeId] = uniqueActions
      acc
    , {}

  _ensureProductTypesInMemory: (products) =>
    Promise.map products, (product) =>
      @_ensureProductTypeInMemory(product.productType.id)
    , {concurrency: 1}

  _ensureDefaultAttributesInProducts: (products) =>
    Promise.map products, (product) =>
      @defaultAttributesService.ensureDefaultAttributesInProduct(product)
    , {concurrency: 1}

  _ensureProductTypeInMemory: (productTypeId) =>
    if @_cache.productType[productTypeId]
      Promise.resolve()
    else
      productType =
        id: productTypeId
      @_resolveReference(@client.productTypes, 'productType', productType, "name=\"#{productType?.id}\"")

  _validateEnums: (products) =>
    enumUpdateActions = {}
    _.each products, (product) =>
      updateActions = @enumValidator.validateProduct(product, @_cache.productType[product.productType.id])
      if updateActions and _.size(updateActions.actions) > 0 then @_updateEnumUpdateActions(enumUpdateActions, updateActions)
    enumUpdateActions

  _updateProductType: (enumUpdateActions) =>
    if _.isEmpty(enumUpdateActions)
      Promise.resolve()
    else
      debug "Updating product type(s): #{_.keys(enumUpdateActions)}"
      Promise.map _.keys(enumUpdateActions), (productTypeId) =>
        updateRequest =
          version: @_cache.productType[productTypeId].version
          actions: enumUpdateActions[productTypeId]
        @client.productTypes.byId(@_cache.productType[productTypeId].id).update(updateRequest)
        .then (updatedProductType) =>
          @_cache.productType[productTypeId] = updatedProductType.body
          @_summary.productTypeUpdated++


  _updateEnumUpdateActions: (enumUpdateActions, updateActions) ->
    if enumUpdateActions[updateActions.productTypeId]
      enumUpdateActions[updateActions.productTypeId] = enumUpdateActions[updateActions.productTypeId].concat(updateActions.actions)
    else
      enumUpdateActions[updateActions.productTypeId] = updateActions.actions

  _fetchSameForAllAttributesOfProductType: (productType) =>
    if @_cache.productType["#{productType.id}_sameForAllAttributes"]
      Promise.resolve(@_cache.productType["#{productType.id}_sameForAllAttributes"])
    else
      @_resolveReference(@client.productTypes, 'productType', productType, "name=\"#{productType?.id}\"")
      .then =>
        sameValueAttributes = _.where(@_cache.productType[productType.id].attributes, {attributeConstraint: "SameForAll"})
        sameValueAttributeNames = _.pluck(sameValueAttributes, 'name')
        @_cache.productType["#{productType.id}_sameForAllAttributes"] = sameValueAttributeNames
        Promise.resolve(sameValueAttributeNames)

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
    .spread (prodCatsIds, taxCatId) =>
      if taxCatId
        productToProcess.taxCategory =
          id: taxCatId
          typeId: 'tax-category'
      if prodCatsIds
        productToProcess.categories = _.map prodCatsIds, (catId) ->
          id: catId
          typeId: 'category'
      productToProcess.slug = @_updateProductSlug productToProcess, existingProduct
      Promise.resolve productToProcess

  _updateProductSlug: (productToProcess, existingProduct) =>
    if @ignoreSlugUpdates
      slug = existingProduct.slug
    else if not productToProcess.slug
      debug 'slug missing in product to process, assigning same as existing product: %s', existingProduct.slug
      slug = existingProduct.slug # to prevent removing slug from existing product.
    else
      slug = productToProcess.slug
    slug

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
        if product.name
          #Promise.reject 'Product name is required.'
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
        resolve(@_cache[refKey][ref.id].id)
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
            @_cache[refKey][ref.id] = result.body.results[0]
            if refKey is 'productType'
              @_cache[refKey][result.body.results[0].id] = result.body.results[0]
            resolve(result.body.results[0].id)

module.exports = ProductImport
