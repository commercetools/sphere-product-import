_ = require 'underscore'
Promise = require 'bluebird'

module.exports.unpublishProduct = (logger, client, product) ->
  if product.masterData.current.published
    logger.debug "unpublish product #{product.id}"
    return client.products.byId(product.id).update({
      version: product.version,
      actions: [
        { action: 'unpublish' }
      ]
    })
  else
    return Promise.resolve(product)

module.exports.deleteProduct = (logger, client, product) ->
  this.unpublishProduct(logger, client, product)
  .then (response) =>
    client.products.byId(response.id).delete(response.version)
    .then (results) ->
      logger.debug "#{_.size results} deleted."
      Promise.resolve()


module.exports.deleteProductById = (logger, client, id) ->
  logger.debug "Deleting product by Id #{id}"
  client.products.byId(id).fetch()
  .then (result) ->
    this.deleteProduct(logger, client, result.body)

module.exports.deleteProducts = (logger, client) ->
  logger.debug "Deleting old product entries..."
  client.products.all().fetch()
  .then (result) ->
    Promise.all _.map result.body.results, (product) ->
      this.deleteProduct(logger, client, product)
  .then (results) ->
    logger.debug "#{_.size results} deleted."
    Promise.resolve()
