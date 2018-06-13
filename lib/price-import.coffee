debug = require('debug')('sphere-price-import')
_ = require 'underscore'
_.mixin require 'underscore-mixins'
Promise = require 'bluebird'
slugify = require 'underscore.string/slugify'
{SphereClient, ProductSync} = require 'sphere-node-sdk'
{Repeater} = require 'sphere-node-utils'
ProductImport = require './product-import'

class PriceImport extends ProductImport

  constructor: (@logger, options = {}) ->
    super @logger, options
    @batchSize = options.batchSize or 30
    @sync.config [{type: 'prices', group: 'white'}].concat(['base', 'references', 'attributes', 'images', 'variants', 'metaAttributes'].map (type) -> {type, group: 'black'})
    @repeater = new Repeater
    @preventRemoveActions = options.preventRemoveActions || false

  _resetSummary: ->
    @_summary =
      unknownSKUCount: 0
      duplicatedSKUs: 0
      variantWithoutPriceUpdates: 0
      updated: 0
      failed: 0

  summaryReport: ->
    "Summary: there were #{@_summary.updated} price update(s). " +
      "(unknown skus: #{@_summary.unknownSKUCount}, duplicate skus: #{@_summary.duplicatedSKUs}, variants without price updates: #{@_summary.variantWithoutPriceUpdates})"

  _processBatches: (prices) ->
    batchedList = _.batchList(prices, @batchSize) # max parallel elements to process
    Promise.map batchedList, (pricesToProcess) =>
      skus = _.map pricesToProcess, (p) -> p.sku
      predicate = @_createProductFetchBySkuQueryPredicate skus
      @client.productProjections
      .where predicate
      .staged true
      .all()
      .fetch()
      .then (results) =>
        queriedEntries = results.body.results
        @_preparePrices(pricesToProcess)
        .then (preparedPrices) =>
          wrappedProducts = @_wrapPricesIntoProducts preparedPrices, queriedEntries
          if @logger then @logger.info "Wrapped #{_.size preparedPrices} price(s) into #{_.size wrappedProducts} existing product(s)."
          @_createOrUpdate wrappedProducts, queriedEntries
          .then (results) =>
            _.each results, (r) =>
              @_handleProcessResponse(r)
            Promise.resolve(@_summary)
    ,{concurrency: 1}

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

  _handleFulfilledResponse: (r) =>
    switch r.value().statusCode
      when 201 then @_summary.created++
      when 200 then @_summary.updated++
      when 404 then @_summary.unknownSKUCount++
      when 304 then @_summary.variantWithoutPriceUpdates++

  _preparePrices: (pricesToProcess) =>
    Promise.map pricesToProcess, (priceToProcess) =>
      @_preparePrice priceToProcess
    , {concurrency: 1}


  _preparePrice: (priceToProcess) =>
    resolvedPrices = []
    Promise.map priceToProcess.prices, (price) =>
      @_resolvePriceReferences(price)
      .then (resolved) ->
        resolvedPrices.push(resolved)
    , {concurrency: 1}
    .then ->
      priceToProcess.prices = resolvedPrices
      Promise.resolve(priceToProcess)


  _resolvePriceReferences: (price) =>
    Promise.all [
      @_resolveReference(@client.customerGroups, 'customerGroup', price.customerGroup, "name=\"#{price.customerGroup?.id}\"")
      @_resolveReference(@client.channels, 'channel', price.channel, "key=\"#{price.channel?.id}\"")
    ]
    .spread (customerGroupId, channelId) ->
      if customerGroupId
        price.customerGroup =
          id: customerGroupId
          typeId: 'customer-group'
      if channelId
        price.channel =
          id: channelId
          typeId: 'channel'
      Promise.resolve price

  _createOrUpdate: (productsToProcess, existingProducts) ->
    debug 'Products to process: %j', {toProcess: productsToProcess, existing: existingProducts}

    posts = _.map productsToProcess, (prodToProcess) =>
      existingProduct = @_isExistingEntry(prodToProcess, existingProducts)

      if existingProduct?
        synced = @sync.buildActions(prodToProcess, existingProduct)
        if synced.shouldUpdate()
          updateTask = (payload) =>
            @client.products.byId(synced.getUpdateId()).update(payload)
          @repeater.execute =>
            payload = synced.getUpdatePayload()
            if @preventRemoveActions
              payload.actions = @_filterPriceActions(payload.actions)
            if @publishingStrategy and @commonUtils.canBePublished(existingProduct, @publishingStrategy)
              payload.actions.push { action: 'publish' }
            updateTask(payload)
          , (e) =>
            if e.statusCode is 409
              debug 'retrying to update %s because of 409', synced.getUpdateId()
              newTask = =>
                @client.productProjections.staged(true)
                .byId(synced.getUpdateId())
                .fetch()
                .then (result) ->
                  newPayload = _.extend {}, synced.getUpdatePayload(), {version: result.body.version}
                  updateTask(newPayload)
              Promise.resolve(newTask)
            else Promise.reject(e) # do not retry in this case
        else
          Promise.resolve statusCode: 304
      else
        @_summary.unknownSKUCount++
        Promise.resolve statusCode: 404

    debug 'About to send %s requests', _.size(posts)
    Promise.settle(posts)

  ###*
   * filters out remove actions
   * so no prices get deleted
  ###
  _filterPriceActions: (actions) ->
    _.filter actions, (action) ->
      action.action != "removePrice"

  _wrapPricesIntoProducts: (prices, products) ->
    sku2index = {}
    _.each prices, (p, index) =>
      if not _.has(sku2index, p.sku)
        sku2index[p.sku] = index
      else
        @logger.warn "Duplicate SKU found - '#{p.sku}' - ignoring!"
        @_summary.duplicatedSKUs++

    productsWithPrices = _.map products, (p) =>
      product = _.deepClone p
      @_wrapPricesIntoVariant product.masterVariant, prices, sku2index
      _.each product.variants, (v) =>
        @_wrapPricesIntoVariant v, prices, sku2index
      product

    # Add prices which were not mapped into any product
    @_summary.unknownSKUCount += Object.keys(sku2index).length
    productsWithPrices

  _wrapPricesIntoVariant: (variant, prices, sku2index) ->
    if _.has(sku2index, variant.sku)
      index = sku2index[variant.sku]
      variant.prices = _.deepClone prices[index].prices
      delete sku2index[variant.sku]
    else
      @_summary.variantWithoutPriceUpdates++

module.exports = PriceImport
