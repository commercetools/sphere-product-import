debug = require('debug')('sphere-product-import:enum-validator')
_ = require 'underscore'
_.mixin require 'underscore-mixins'
Promise = require 'bluebird'
slugify = require 'underscore.string/slugify'
{SphereClient, ProductSync} = require 'sphere-node-sdk'

class EnumValidator

  constructor: (@logger, @client) ->
    @_resetCache()
    if @logger then @logger.info "Enum Validator initialized."

  _resetCache: ->
    @_cache =
      productTypeEnumMap: {}

  validateProduct: (product, productType) =>
    # to validate a product enums we need:
      # product type of that product
      # attribute names of type enum or lenum or set of enum or set of lenum
      #

module.exports = EnumValidator
