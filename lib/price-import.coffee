debug = require('debug')('sphere-price-import')
_ = require 'underscore'
_.mixin require 'underscore-mixins'
Promise = require 'bluebird'
slugify = require 'underscore.string/slugify'
{SphereClient, ProductSync} = require 'sphere-node-sdk'
ProductImport = require './product-import'

class PriceImport extends ProductImport

  constructor: (@logger, options = {}) ->
    super(@logger, options)
    @skuOfPerformedPrices = []
    @sync.config [{type: 'prices', group: 'white'}].concat(['base', 'references', 'attributes', 'images', 'variants', 'metaAttributes'].map (type) -> {type, group: 'black'})

  _processBatches: (prices) ->
    batchedList = _.batchList(prices, 30) # max parallel elements to process
    Promise.map batchedList, (pricesToProcess) =>
      skus = @_extractUniqueSkus(pricesToProcess)
      predicate = @_createProductFetchBySkuQueryPredicate(skus)
      @client.productProjections
      .where(predicate)
      .staged(true)
      .all()
      .fetch()
      .then (results) =>
        debug "Fetched products: %j", results
        queriedEntries = results.body.results
        wrappedProducts = @_wrapPricesIntoProducts(pricesToProcess, queriedEntries)
        console.log "Wrapped #{_.size prices} price(s) into #{_.size wrappedProducts} existing product(s)."
        @_createOrUpdate wrappedProducts, queriedEntries
        .then (results) =>
          _.each results, (r) =>
            switch r.statusCode
              when 201 then @_summary.created++
              when 200 then @_summary.updated++
          Promise.resolve('huhu')
    ,{concurrency: 1}

  _extractUniqueSkus: (prices) ->
    _.map prices, (p) ->
      p.sku

  _wrapPricesIntoProducts: (prices, products) ->
    sku2index = {}
    _.each prices, (p, index) ->
      if not _.has(sku2index, p.sku)
        sku2index[p.sku] = []
      sku2index[p.sku].push index

    _.map products, (p) =>
      product = _.deepClone p
      @_wrapPriceIntoVariant product.masterVariant, prices, sku2index
      _.each product.variants, (v) =>
        @_wrapPriceIntoVariant v, prices, sku2index
      product

  _wrapPriceIntoVariant: (variant, prices, sku2index) ->
    if _.has(sku2index, variant.sku)
      if not _.contains(@skuOfPerformedPrices, variant.sku)
        variant.prices = []
        @skuOfPerformedPrices.push variant.sku
      _.each sku2index[variant.sku], (index) ->
        price = _.deepClone prices[index]
        delete price.sku
        variant.prices.push price
    else
      variant.prices = []

module.exports = PriceImport