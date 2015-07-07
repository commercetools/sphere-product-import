debug = require('debug')('sphere-price-import')
_ = require 'underscore'
_.mixin require 'underscore-mixins'
Promise = require 'bluebird'
slugify = require 'underscore.string/slugify'
{SphereClient, ProductSync} = require 'sphere-node-sdk'

class PriceImport

  constructor: (@logger, options = {}) ->
    @sync = new ProductSync
    @sync.config [{type: 'prices', group: 'white'}].concat(['base', 'references', 'attributes', 'images', 'variants', 'metaAttributes'].map (type) -> {type, group: 'black'})
    @client = new SphereClient options
    @_resetSummary()

  _resetSummary: ->
    @_summary =
      emptySKU: 0
      unknownSKUCount: 0
      created: 0
      updated: 0


  performStream: (chunk, cb) ->
    @_processBatches(chunk).then -> cb()

  @_processBatches(prices) ->
    batchedList = _.batchList(prices, 30) # max parallel elements to process
    Promise.map batchedList, (pricesToProcess) =>
      @_wrapPricesIntoProducts(pricesToProcess)
      .then (wrappedProducts) =>
        skus = @_extractUniqueSkus(wrappedProducts)
        predicate = @_createProductFetchBySkuQueryPredicate(skus)
        @client.productProjections
        .where(predicate)
        .staged(true)
        .fetch()
        .then (results) =>
          debug 'Fetched products: %j', results
          queriedEntries = results.body.results
          @_createOrUpdate wrappedProducts, queriedEntries
          .then (results) =>
            _.each results, (r) =>
              switch r.statusCode
                when 201 then @_summary.created++
                when 200 then @_summary.updated++
            Promise.resolve()
    ,{concurrency: 1}



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
        @_summary.unknownSKUCount++
        Promise.resolve statusCode: 404

    debug 'About to send %s requests', _.size(posts)
    Promise.all(posts)


  _wrapPricesIntoProducts: (prices) ->
    new Promise(resolve, reject) ->
      products = []
      # Some wrapping magic from @Hajo
      resolve products


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

module.exports = PriceImport