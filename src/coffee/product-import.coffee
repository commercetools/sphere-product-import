debug = require('debug')('sphere-product-sync-import')
_ = require 'underscore'
_.mixin require('underscore-mixins')
Promise = require 'bluebird'
{SphereClient, ProductSync} = require 'sphere-node-sdk'

class ProductImport

  constructor: (@logger, options = {}) ->
    @sync = new ProductSync
    @client = new SphereClient options

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
      skus.push product.masterVariant?.sku
      for variant in product.variants
        skus.push variant.sku
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
          @client.productsToProcess.byId(synced.getUpdateId()).update(synced.getUpdatePayload())
        else
          Promise.resolve statusCode: 304
      else
        @client.productsToProcess.create(prodToProcess)

    debug 'About to send %s requests', _.size(posts)
    Promise.all(posts)




module.exports = ProductImport
