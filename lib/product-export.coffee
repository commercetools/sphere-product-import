debug = require('debug')('sphere-product-export')
_ = require 'underscore'
_.mixin require 'underscore-mixins'
Promise = require 'bluebird'
slugify = require 'underscore.string/slugify'
{SphereClient} = require 'sphere-node-sdk'
CommonUtils = require './common-utils'

class ProductExport

  constructor: (@logger, options = {}) ->
    @commonUtils = new CommonUtils @logger
    @client = new SphereClient @commonUtils.extendUserAgent options

  # `cb` should return a Promise
  processStream: (cb) ->
    # TODO: make it configurable (query)
    @client.productProjections
    .staged(true)
    .process cb, {accumulate: false}

module.exports = ProductExport
