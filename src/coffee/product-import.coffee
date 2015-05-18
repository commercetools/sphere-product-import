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
      debug 'Chunk: %j', productsToProcess
      # extract all skus from master variant and variants of all jsons in the batch

      debug 'Chunk (unique products): %j', uniqueProductsToProcessBySku

      skus = _.map uniqueProductsToProcessBySku, (s) =>
        @_summary.emptySKU++ if _.isEmpty s.sku
        # TODO: query also for channel?
        "\"#{s.sku}\""
      predicate = "sku in (#{skus.join(', ')})"
      # masterVariant(sku="M0E20000000E30L") or variants(sku="M0E20000000E30L")
      # masterVariant(sku in ("B3-717597", "B3-717487")) or variants(sku in ("B3-717597", "B3-717487"))
      @client.products
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
    predicate = {}
    skuString = "sku in (\"#{skus.join('", "')}\")"
    predicate.predicateString = "masterVariant(#{skuString}) or variants(#{skuString})"
    predicate.byteSize = Buffer.byteLength(predicate.predicateString,'utf-8')
    return predicate

  _extractUniqueSkus: (products) ->
    skus = []
    for product in products
      skus.push product.masterVariant?.sku
      for variant in product?.variants
        skus.push variant.sku
    return _.uniq(skus,false)


  _uniqueProductsBySku: (products) ->
    _.reduce products, (acc, product) ->
      foundProduct = _.find acc, (p) -> p.sku is product.sku
      acc.push product unless foundProduct
      acc
    , []


  _match: (entry, existingEntries) ->
    _.find existingEntries, (existingEntry) ->
      if entry.sku is existingEntry.sku
        true
      else
        false

  _createOrUpdate: (productsToProcess, existingEntries) ->
    debug 'Products to process: %j', {toProcess: productsToProcess, existing: existingEntries}

    posts = _.map productsToProcess, (entry) =>
      existingEntry = @_match(entry, existingEntries)
      if existingEntry?
        synced = @sync.buildActions(entry, existingEntry)
        if synced.shouldUpdate()
          @client.productsToProcess.byId(synced.getUpdateId()).update(synced.getUpdatePayload())
        else
          Promise.resolve statusCode: 304
      else
        @client.productsToProcess.create(entry)

    debug 'About to send %s requests', _.size(posts)
    Promise.all(posts)




module.exports = ProductImport
