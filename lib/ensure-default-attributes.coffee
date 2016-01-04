_ = require 'underscore'
_.mixin require 'underscore-mixins'
Promise = require 'bluebird'

# Recives list of default attributes in the format:
# [{ name: attributeName, value: defaultAttributeValue }, { name: attributeName, value: defaultAttributeValue }]
class EnsureDefaultAttributes

  constructor: (@logger, @defaultAttributes) ->
    @logger.debug('Ensuring default attributes')

  ensureDefaultAttributesInProduct: (product) =>
    updatedProduct = _.deepClone(product)
    updatedProduct.masterVariant = @_ensureInVariant(product.masterVariant)
    updatedVariants = _.map(product.variants, @_ensureInVariant)
    updatedProduct.variants = updatedVariants
    Promise.resolve(updatedProduct)

  _ensureInVariant: (variant) =>
    if not variant.attributes
      return variant
    extendedAttributes = _.deepClone(variant.attributes)
    for defaultAttribute in @defaultAttributes
      if not @_isAttributeExisting(defaultAttribute, variant.attributes)
        extendedAttributes.push(defaultAttribute)
    variant.attributes = extendedAttributes
    return variant

  _isAttributeExisting: (defaultAttribute, attributeList) ->
    _.findWhere(attributeList, { name: "#{defaultAttribute.name}" })

module.exports = EnsureDefaultAttributes