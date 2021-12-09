debug = require('debug')('sphere-discount-import')
_ = require 'underscore'
_.mixin require 'underscore-mixins'
Promise = require 'bluebird'
slugify = require 'underscore.string/slugify'
{SphereClient} = require 'sphere-node-sdk'
{Repeater} = require 'sphere-node-utils'
CommonUtils = require './common-utils'

class ProductDiscountImport

  constructor: (@logger, options = {}) ->
    @commonUtils = new CommonUtils @logger
    @client = new SphereClient @commonUtils.extendUserAgent options.clientConfig
    @language = 'en'
    @_resetSummary()

  _resetSummary: ->
    @_summary =
      created: 0
      updated: 0
      unChanged: 0

  summaryReport: ->
    if @_summary.updated is 0
      message = 'Summary: nothing to update'
    else
      message = "Summary: there were #{@_summary.updated} update(s) and #{@_summary.created} creation(s) of product discount."

    message

  performStream: (chunk, cb) ->
    @_processBatches(chunk)
    .then -> cb()
    .catch (err) -> cb(err.body)

  _createProductDiscountFetchByNamePredicate: (discounts) ->
    names = _.map discounts, (d) =>
      "\"#{d.name[@language]}\""
    "name(#{@language} in (#{names.join(', ')}))"

  _processBatches: (discounts) ->
    batchedList = _.batchList(discounts, 30) # max parallel elements to process
    Promise.map batchedList, (discountsToProcess) =>
      predicate = @_createProductDiscountFetchByNamePredicate discountsToProcess
      @client.productDiscounts
      .where(predicate)
      .all()
      .fetch()
      .then (results) =>
        debug "Fetched product discounts: %j", results
        queriedEntries = results.body.results
        @_createOrUpdate discountsToProcess, queriedEntries
        .then (results) =>
          _.each results, (r) =>
            switch r.statusCode
              when 200 then @_summary.updated++
              when 201 then @_summary.created++
              when 304 then @_summary.unChanged++
          Promise.resolve(@_summary)
    ,{concurrency: 1}

  _findMatch: (discount, existingDiscounts) ->
    _.find existingDiscounts, (d) =>
      _.isString(d.name[@language]) and
      d.name[@language] is discount.name[@language]

  _createOrUpdate: (discountsToProcess, existingDiscounts) ->
    debug 'Product discounts to process: %j', {toProcess: discountsToProcess, existing: existingDiscounts}

    posts = _.map discountsToProcess, (discount) =>
      existingDiscount = @_findMatch(discount, existingDiscounts)
      if existingDiscount?
        if discount.predicate is existingDiscount.predicate
          Promise.resolve statusCode: 304
        else
          payload =
            version: existingDiscount.version
            actions: [
              { action: 'changePredicate', predicate: discount.predicate }
            ]
          @client.productDiscounts
          .byId(existingDiscount.id)
          .update(payload)
      else
        @client.productDiscounts
        .create(discount)

    debug 'About to send %s requests', _.size(posts)
    Promise.all(posts)

module.exports = ProductDiscountImport
