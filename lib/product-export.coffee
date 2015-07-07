debug = require('debug')('sphere-product-export')
_ = require 'underscore'
_.mixin require 'underscore-mixins'
Promise = require 'bluebird'
slugify = require 'underscore.string/slugify'
{SphereClient} = require 'sphere-node-sdk'

class ProductExport

  constructor: (@logger, options = {}) ->
    @client = new SphereClient options

  # `cb` should return a Promise
  processStream: (cb) ->
    # TODO: make it configurable (query)
    @client.productProjections
    .staged(true)
    .process cb, {accumulate: false}

module.exports = ProductExport
