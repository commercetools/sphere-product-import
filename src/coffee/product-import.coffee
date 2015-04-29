debug = require('debug')('sphere-product-sync-import')
Promise = require 'bluebird'
{SphereClient, ProductSync} = require 'sphere-node-sdk'

class ProductImport

  constructor: (@logger, options = {}) ->
    @sync = new ProductSync
    @client = new SphereClient options

module.exports = ProductImport
