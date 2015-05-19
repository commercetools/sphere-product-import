debug = require('debug')('sphere-product-sync-import')
_ = require 'underscore'
_.mixin require('underscore-mixins')
Promise = require 'bluebird'
{SphereClient, ProductSync} = require 'sphere-node-sdk'

class ProductImport

  constructor: (@logger, options = {}) ->
    @sync = new ProductSync
    @client = new SphereClient options
    @_cache = {}

  _resetSummary: ->
    @_summary =
      emptySKU: 0
      created: 0
      updated: 0


  performStream: (chunk, cb) ->
    @_processBatches(chunk).then -> cb()

  _processBatches: (products) ->
    batchedList = _.batchList(products, 30) # max parallel elem to process
    Promise.map batchedList, (productsToProcess) =>
      # extract all skus from master variant and variants of all jsons in the batch
      skus = @_extractUniqueSkus(productsToProcess)
      predicate = @_prepareProductFetchBySkuQueryPredicate(skus)
      # Check predicate size by: Buffer.byteLength(predicate,'utf-8')
      # Todo: Handle predicate if predicate size > 8kb
      # Fetch products from product projections end point by list of skus.
      @client.productProjections
      .where(predicate)
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


  _prepareProductFetchBySkuQueryPredicate: (skus) ->
    skuString = "sku in (\"#{skus.join('", "')}\")"
    return "masterVariant(#{skuString}) or variants(#{skuString})"

  _extractUniqueSkus: (products) ->
    skus = []
    for product in products
      skus.push(product.masterVariant.sku) if product.masterVariant?.sku
      for variant in product.variants
        skus.push(variant.sku) if variant.sku
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
        synced = @sync.buildActions(prodToProcess, existingProduct)
        if synced.shouldUpdate()
          @client.products.byId(synced.getUpdateId()).update(synced.getUpdatePayload())
        else
          Promise.resolve statusCode: 304
      else
        @client.products.create(@_prepareNewProduct(prodToProcess))

    debug 'About to send %s requests', _.size(posts)
    Promise.all(posts)

  _prepareNewProduct: (product) ->
    Promise.all [
      @_resolveProductTypeReference(product.productType?)
      @_resolveProductCategories(product.categories?)
      @_resolveTaxCategoryReference(product.taxCategory?)
    ]
    .spread(prodType, prodCats, taxCat) =>
      if not prodType.isRejected
        product.productType = prodType.value
      if not prodCats.isRejected
        product.categories = prodCats.value
      if not taxCat.isRejected
        product.taxCategory = taxCat.value


  _resolveProductTypeReference: (productTypeRef) ->
    new Promise (resolve, reject) =>
      if not productTypeRef?
        reject("Product type reference is undefined")
      if @_cache.productType[productTypeRef.id]
        resolve(@_cache.productType[productTypeRef.id])
      else
        @client.productTypes.where("name=\"#{productTypeRef.id}\"").fetch()
        .then(result) =>
          # Todo: Handle multiple response, currently taking first response.
          @_cache.productType[productTypeRef.id] = result.results[0]
          resolve(result.results[0])


  _resolveProductCategories: (cats) ->
    new Promise (resolve, reject) =>
      if not cats?
        reject("Product categories are undefined.")
      else
        Promise.all [
          for cat in cats
            @_resolveProductCategories(cat)
        ].then(result) =>
          resolve(result)

  _resolveProductCategoryReference: (categoryRef) ->
    new Promise (resolve, reject) =>
      if not categoryRef?
        reject("Product category is undefined")
      if @_cache.productCategory[categoryRef.id]
        resolve(@_cache.productCategory[categoryRef.id])
      else
        @client.categories.where("externalId=\"#{categoryRef.id}\"").fetch()
        .then(result) =>
          # Todo: Handle multiple response, currently taking first response.
          @_cache.productCategory[categoryRef.id] = result.results[0]
          resolve(result.results[0])


  _resolveTaxCategoryReference: (taxCategoryRef) ->
    new Promise (resolve, reject) =>
      if not taxCategoryRef?
        reject("Tax category is undefined")
      if @_cache.taxCategory[taxCategoryRef.id]
        resolve(@_cache.taxCategory[taxCategoryRef.id])
      else
        @client.taxCategories.where("name=\"#{taxCategoryRef.id}\"").fetch()
        .then(result) =>
          # Todo: Handle multiple response, currently taking first response.
          @_cache.taxCategory[taxCategoryRef.id] = result.results[0]
          resolve(result.results[0])

module.exports = ProductImport
