debug = require('debug')('sphere-product-import')
_ = require 'underscore'
_.mixin require 'underscore-mixins'
Promise = require 'bluebird'
slugify = require 'underscore.string/slugify'
{SphereClient, ProductSync} = require 'sphere-node-sdk'
{Repeater} = require 'sphere-node-utils'
fs = require 'fs-extra'
path = require 'path'
serializeError = require 'serialize-error'
EnumValidator = require './enum-validator'
UnknownAttributesFilter = require './unknown-attributes-filter'
CommonUtils = require './common-utils'
EnsureDefaultAttributes = require './ensure-default-attributes'
util = require 'util'

class ProductImport

  constructor: (@logger, options = {}) ->
    @sync = new ProductSync
    if options.blackList and ProductSync.actionGroups
      @sync.config @_configureSync(options.blackList)
    @errorCallback = options.errorCallback or @_errorLogger
    @ensureEnums = options.ensureEnums or false
    @filterUnknownAttributes = options.filterUnknownAttributes or false
    @ignoreSlugUpdates = options.ignoreSlugUpdates or false
    @batchSize = options.batchSize or 30
    @failOnDuplicateAttr = options.failOnDuplicateAttr or false
    @logOnDuplicateAttr = if options.logOnDuplicateAttr? then options.logOnDuplicateAttr else true
    @client = new SphereClient options.clientConfig
    @enumValidator = new EnumValidator @logger
    @unknownAttributesFilter = new UnknownAttributesFilter @logger
    @commonUtils = new CommonUtils @logger
    @filterActions = if _.isFunction(options.filterActions)
      options.filterActions
    else if _.isArray(options.filterActions)
      (action) -> !_.contains(options.filterActions, action.action)
    else
      (action) -> true
    # default web server url limit in bytes
    # count starts after protocol (eg. https:// does not count)
    @urlLimit = 8192
    if options.defaultAttributes
      @defaultAttributesService = new EnsureDefaultAttributes @logger, options.defaultAttributes
    # possible values:
    # always, publishedOnly, stagedAndPublishedOnly
    @publishingStrategy = options.publishingStrategy or false
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
      productsWithMissingSKU: 0
      created: 0
      updated: 0
      failed: 0
      productTypeUpdated: 0
      errorDir: @errorDir
    if @filterUnknownAttributes then @_summary.unknownAttributeNames = []

  summaryReport: (filename) ->
    message = "Summary: there were #{@_summary.created + @_summary.updated} imported products " +
      "(#{@_summary.created} were new and #{@_summary.updated} were updates)."

    if @_summary.productsWithMissingSKU > 0
      message += "\nFound #{@_summary.productsWithMissingSKU} product(s) which do not have SKU and won't be imported."
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
        # filter out products which do not have SKUs on all variants
        originalLength = productsToProcess.length
        productsToProcess = productsToProcess.filter(@_doesProductHaveSkus)
        filteredProductsLength = originalLength - productsToProcess.length

        # if there are some products which do not have SKU
        if filteredProductsLength
          @logger.warn "Filtering out #{filteredProductsLength} product(s) which do not have SKU"
          @_summary.productsWithMissingSKU += filteredProductsLength

        skus = @_extractUniqueSkus(productsToProcess)
        if skus.length then @_getExistingProductsForSkus(skus) else []
      .then (queriedEntries) =>
        if @defaultAttributesService
          debug 'Ensuring default attributes'
          @_ensureDefaultAttributesInProducts(productsToProcess, queriedEntries)
          .then ->
            Promise.resolve(queriedEntries)
        else
          Promise.resolve(queriedEntries)
      .then (queriedEntries) =>
        @_createOrUpdate productsToProcess, queriedEntries
      .then (results) =>
        _.each results, (r) =>
          @_handleProcessResponse(r)
        Promise.resolve(@_summary)
    , { concurrency: 1 } # run 1 batch at a time

  _getWhereQueryLimit: ->
    client = @client.productProjections
    .where('a')
    .staged(true)

    url = _.clone(@client.productProjections._rest._options.uri)
    url = url.replace(/.*?:\/\//g, "")
    url += @client.productProjections._currentEndpoint
    url += "?" + @client.productProjections._queryString()

    @client.productProjections._setDefaults()
    # subtract 1 since we added 'a' as the where query
    return @urlLimit - Buffer.byteLength((url),'utf-8') - 1

  _getExistingProductsForSkus: (skus) =>
    new Promise (resolve, reject) =>
      skuChunks = @commonUtils._separateSkusChunksIntoSmallerChunks(
        skus,
        @_getWhereQueryLimit()
      )
      Promise.map(skuChunks, (skus) =>
        predicate = @_createProductFetchBySkuQueryPredicate(skus)
        @client.productProjections
        .where(predicate)
        .staged(true)
        .perPage(200)
        .all()
        .fetch()
        .then (res) ->
          res.body.results
      , { concurrency: 30 })
      .then (results) ->
        debug 'Fetched products: %j', results
        resolve(_.flatten(results))
      .catch (err) -> reject(err)

  _errorLogger: (res, logger) =>
    if @_summary.failed < @errorLimit or @errorLimit is 0
      logger.error res, "Skipping product due to an error"
    else
      logger.warn "
        Error not logged as error limit of #{@errorLimit} has reached.
      "

  _handleProcessResponse: (res) =>
    if res.isFulfilled()
      @_handleFulfilledResponse(res)
    else if res.isRejected()
      error = serializeError res.reason()

      @_summary.failed++
      if @errorDir
        errorFile = path.join(@errorDir, "error-#{@_summary.failed}.json")
        fs.outputJsonSync(errorFile, error, {spaces: 2})

      if _.isFunction(@errorCallback)
        @errorCallback(error, @logger)
      else
        @logger.error "Error callback has to be a function!"

  _handleFulfilledResponse: (res) =>
    switch res.value().statusCode
      when 201 then @_summary.created++
      when 200 then @_summary.updated++

  _createProductFetchBySkuQueryPredicate: (skus) ->
    skuString = "sku in (#{skus.map((val) -> JSON.stringify(val))})"
    "masterVariant(#{skuString}) or variants(#{skuString})"

  _doesProductHaveSkus: (product) ->
    if product.masterVariant and not product.masterVariant.sku
      return false

    if product.variants?.length
      for variant in product.variants
        if not variant.sku
          return false
    true

  _extractUniqueSkus: (products) ->
    skus = []
    for product in products
      if product.masterVariant?.sku
        skus.push(product.masterVariant.sku)
      if product.variants?.length
        for variant in product.variants
          if variant.sku
            skus.push(variant.sku)
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

  _updateProductRepeater: (prodToProcess, existingProduct) ->
    repeater = new Repeater {attempts: 5}
    repeater.execute =>
      @_updateProduct(prodToProcess, existingProduct)
    , (e) =>
      if e.statusCode isnt 409 # concurrent modification
        return Promise.reject e

      @logger.warn "Recovering from 409 concurrentModification error on product '#{existingProduct.id}'"

      Promise.resolve => # next task must be a function
        @client.productProjections.staged(true).byId(existingProduct.id).fetch()
        .then (result) =>
          @_updateProduct(prodToProcess, result.body, true)

  _updateProduct: (prodToProcess, existingProduct, productIsPrepared) ->
    @_fetchSameForAllAttributesOfProductType(prodToProcess.productType)
    .then (sameForAllAttributes) =>
      productPromise = Promise.resolve(prodToProcess)

      if not productIsPrepared
        productPromise = @_prepareUpdateProduct(prodToProcess, existingProduct)

      productPromise
      .then (preparedProduct) =>
        synced = @sync.buildActions(preparedProduct, existingProduct, sameForAllAttributes)
          .filterActions (action) =>
            @filterActions(action, existingProduct, preparedProduct)
        if synced.shouldUpdate()
          @_updateInBatches(synced.getUpdateId(), synced.getUpdatePayload())
        else
          Promise.resolve statusCode: 304

  _updateInBatches: (id, updateRequest) ->
    latestVersion = updateRequest.version
    batchedActions = _.batchList(updateRequest.actions, 500) # max 500 actions per update request

    Promise.mapSeries batchedActions, (actions) =>
      request =
        version: latestVersion
        actions: actions

      @client.products
        .byId(id)
        .update(request)
        .tap (res) ->
          latestVersion = res.body.version
    .then _.last # return only the last result

  _cleanVariantAttributes: (variant) ->
    attributeMap = []

    if _.isArray(variant.attributes)
      variant.attributes = variant.attributes.filter (attribute) =>
        isDuplicate = attributeMap.indexOf(attribute.name) >= 0
        attributeMap.push(attribute.name)

        if isDuplicate
          msg = "Variant with SKU '#{variant.sku}' has duplicate attributes with name '#{attribute.name}'."
          if @failOnDuplicateAttr
            throw new Error(msg)
          else if @logOnDuplicateAttr
            @logger.warn msg
        # filter out duplicate attributes
        not isDuplicate

  _cleanDuplicateAttributes: (prodToProcess) ->
    prodToProcess.variants = prodToProcess.variants || []

    @_cleanVariantAttributes prodToProcess.masterVariant
    prodToProcess.variants.forEach (variant) =>
      @_cleanVariantAttributes variant

  _createOrUpdate: (productsToProcess, existingProducts) ->
    debug 'Products to process: %j', {toProcess: productsToProcess, existing: existingProducts}

    posts = _.map productsToProcess, (product) =>
      @_filterAttributes(product)
      .then (prodToProcess) =>
        # will filter out duplicate attributes
        @_cleanDuplicateAttributes(prodToProcess)
        existingProduct = @_isExistingEntry(prodToProcess, existingProducts)
        if existingProduct?
          @_updateProductRepeater(prodToProcess, existingProduct)
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

  _ensureDefaultAttributesInProducts: (products, queriedEntries) =>
    if queriedEntries
      queriedEntries = _.compact(queriedEntries)
    Promise.map products, (product) =>
      if queriedEntries?.length > 0
        uniqueSkus = @_extractUniqueSkus([product])
        productFromServer = _.find(queriedEntries, (entry) =>
          serverUniqueSkus = @_extractUniqueSkus([entry])
          intersection = _.intersection(uniqueSkus, serverUniqueSkus)
          return _.compact(intersection).length > 0
        )
      @defaultAttributesService.ensureDefaultAttributesInProduct(product, productFromServer)
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
    if (productToProcess.state)
      stateRef = productToProcess.state
      statePredicate = "id=\"#{productToProcess.state.id}\" and type=\"ProductState\""
    else
      stateRef = { id: existingProduct.state.id }
      statePredicate = "id=\"#{existingProduct.state.id}\" and type=\"ProductState\""

    Promise.all [
      @_resolveProductCategories(productToProcess.categories)
      @_resolveReference(@client.taxCategories, 'taxCategory', productToProcess.taxCategory, "name=\"#{productToProcess.taxCategory?.id}\"")
      @_resolveReference(@client.states, 'state', stateRef, statePredicate)
      @_fetchAndResolveCustomReferences(productToProcess)
    ]
    .spread (prodCatsIds, taxCatId, stateId) =>
      @_assignCommonIds(productToProcess, taxCatId, prodCatsIds, stateId)
      productToProcess.slug = @_updateProductSlug productToProcess, existingProduct
      Promise.resolve productToProcess

  _assignCommonIds: (productToProcess, taxCatId, prodCatsIds, stateId) ->
    if taxCatId
      productToProcess.taxCategory =
        id: taxCatId
        typeId: 'tax-category'
    if prodCatsIds
      productToProcess.categories = _.map prodCatsIds, (catId) ->
        id: catId
        typeId: 'category'
    productToProcess.state =
      id: stateId
      typeId: 'state'

  _updateProductSlug: (productToProcess, existingProduct) =>
    if @ignoreSlugUpdates
      slug = existingProduct.slug
    else if not productToProcess.slug
      debug 'slug missing in product to process, assigning same as existing product: %s', existingProduct.slug
      slug = existingProduct.slug # to prevent removing slug from existing product.
    else
      slug = productToProcess.slug
    slug

  _prepareNewProduct: (productToProcess) ->
    productToProcess = @_ensureDefaults(productToProcess)
    if (productToProcess.state)
      stateRef = productToProcess.state
      statePredicate = "id=\"#{productToProcess.state.id}\" and type=\"ProductState\""
    else
      stateRef = ''
      statePredicate = 'key="New" and type="ProductState"'

    Promise.all [
      @_resolveReference(@client.productTypes, 'productType', productToProcess.productType, "name=\"#{productToProcess.productType?.id}\"")
      @_resolveProductCategories(productToProcess.categories)
      @_resolveReference(@client.taxCategories, 'taxCategory', productToProcess.taxCategory, "name=\"#{productToProcess.taxCategory?.id}\"")
      @_resolveReference(@client.states, 'state', stateRef, statePredicate)
      @_fetchAndResolveCustomReferences(productToProcess)
    ]
    .spread (prodTypeId, prodCatsIds, taxCatId, stateId) =>
      @_assignCommonIds(productToProcess, taxCatId, prodCatsIds, stateId)
      if prodTypeId
        productToProcess.productType =
          id: prodTypeId
          typeId: 'product-type'
      if not productToProcess.slug
        if productToProcess.name
          #Promise.reject 'Product name is required.'
          productToProcess.slug = @_generateSlug productToProcess.name
      Promise.resolve productToProcess


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

  _fetchAndResolveCustomAttributeReferences: (variant) ->
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

  _fetchAndResolveCustomPriceReferences: (variant) ->
    if variant.prices and not _.isEmpty(variant.prices)
      Promise.map variant.prices, (price) =>
        if price and price.custom and price.custom.type and price.custom.type.id
          service = @client.types
          ref = { id: price.custom.type.id}
          @_resolveReference(service, "types", ref, "key=\"#{ref.id}\"")
          .then (refId) ->
            price.custom.type.id = refId
            Promise.resolve(price)
        else
          Promise.resolve(price)
      .then (prices) ->
        Promise.resolve _.extend(variant, { prices })
    else
      Promise.resolve(variant)


  _fetchAndResolveCustomReferencesByVariant: (variant) ->
    @_fetchAndResolveCustomAttributeReferences(variant)
    .then (variant) =>
      @_fetchAndResolveCustomPriceReferences(variant)

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
    new Promise (resolve, reject) =>
      if _.isEmpty(cats)
        resolve()
      else
        Promise.all cats.map (cat) =>
          @_resolveReference(@client.categories, 'categories', cat, "externalId=\"#{cat.id}\"")
        .then (result) -> resolve(result.filter (c) -> c)
        .catch (err) -> reject(err)

  _resolveReference: (service, refKey, ref, predicate) ->
    new Promise (resolve, reject) =>
      if not @_cache[refKey]
        @_cache[refKey] = {}
      if not ref
        if (refKey is 'state') # References are needed to states even if the incoming product doesn't itself (yet) have one.
          @_resolveStateReferenceForProductWithoutOne(service, refKey, predicate, resolve, reject)
        else
          resolve()
      else
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

  _resolveStateReferenceForProductWithoutOne: (service, refKey, predicate, resolve, reject) =>
    if @_cache[refKey][predicate]
      if (typeof @_cache[refKey][predicate] is 'object' and @_cache[refKey][predicate].constructor.name is 'Promise')
        @_cache[refKey][predicate].then (result) =>
          @_processCompletedStateRequest(refKey, predicate, result, resolve, reject)
      else
        resolve(@_cache[refKey][predicate].id)
    else
      request = service.where(predicate)
      fetch = request.fetch()
      @_cache[refKey][predicate] = fetch
      fetch.then (result) =>
        @_processCompletedStateRequest(refKey, predicate, result, resolve, reject)

  _processCompletedStateRequest: (refKey, predicate, result, resolve, reject) =>
    if result.body.count is 0
      reject "Didn't find any match while resolving #{refKey} (#{predicate})"
    else
      if _.size(result.body.results) > 1
        @logger.warn "Found more than 1 #{refKey} for #{predicate}"
      @_cache[refKey][result.body.results[0].id] = result.body.results[0] # Cache by ID for future calls where it's known
      @_cache[refKey][predicate] = result.body.results[0] # Cache by predicate for where (as here) it's not
      resolve(result.body.results[0].id)

module.exports = ProductImport