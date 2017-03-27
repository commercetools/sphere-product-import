_ = require 'underscore'
Promise = require 'bluebird'

unpublishProduct = (logger, client, product) ->
  if product.masterData.published
    logger.debug "unpublish product #{product.id}"
    return client.products.byId(product.id).update({
      version: product.version,
      actions: [
        { action: 'unpublish' }
      ]
    })
  else
    return Promise.resolve(product)

deleteProduct = (logger, client, product) ->
  unpublishProduct(logger, client, product)
  .then (response) ->
    client.products.byId(response.id).delete(response.version)
    .then (results) ->
      logger.debug "#{_.size results} deleted."
      Promise.resolve()


deleteProductById = (logger, client, id) ->
  logger.debug "Deleting product by Id #{id}"
  client.products.byId(id).fetch()
  .then (result) ->
    deleteProduct(logger, client, result.body)

deleteProducts = (logger, client) ->
  logger.debug "Deleting old product entries..."
  client.products.all().fetch()
  .then (result) ->
    Promise.all _.map result.body.results, (product) ->
      deleteProduct(logger, client, product)
  .then (results) ->
    logger.debug "#{_.size results} deleted."
    Promise.resolve()



module.exports =
  unpublishProduct: unpublishProduct
  deleteProduct: deleteProduct
  deleteProducts: deleteProducts
  deleteProductById: deleteProductById
