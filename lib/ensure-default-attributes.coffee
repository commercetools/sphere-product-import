_ = require 'underscore'
_.mixin require 'underscore-mixins'
Promise = require 'bluebird'

# Receives list of default attributes in the format:
# [{ name: attributeName, value: defaultAttributeValue }, { name: attributeName, value: defaultAttributeValue }]
class EnsureDefaultAttributes

  constructor: (@logger, @defaultAttributes) ->
    @logger.debug('Ensuring default attributes')

  ensureDefaultAttributesInProduct: (product, productFromServer) =>
    updatedProduct = _.deepClone(product)
    if productFromServer
      masterVariant = productFromServer.masterVariant
    updatedProduct.masterVariant = @_ensureInVariant(product.masterVariant, masterVariant)
    updatedVariants = _.map(product.variants,
      (variant) =>
        if productFromServer
          serverVariant = productFromServer.variants.filter((v) -> v.sku == variant.sku)[0]
        @_ensureInVariant(variant, serverVariant)
    )
    updatedProduct.variants = updatedVariants
    Promise.resolve(updatedProduct)

  _ensureInVariant: (variant, serverVariant) =>
    # This variable gets updated in the _updateAttribute method
    # so we should ensure that the original @defaultAttributes won't change
    # because they can be used later also on other products
    defaultAttributes = _.deepClone(@defaultAttributes)
    if not variant.attributes
      return variant
    extendedAttributes = _.deepClone(variant.attributes)
    if serverVariant
      serverAttributes = serverVariant.attributes
    for defaultAttribute in defaultAttributes
      if not @_isAttributeExisting(defaultAttribute, variant.attributes)
        @_updateAttribute(serverAttributes, defaultAttribute, extendedAttributes)
    variant.attributes = extendedAttributes
    return variant

  _updateAttribute: (serverAttributes, defaultAttribute, extendedAttributes) ->
    if serverAttributes
      serverAttribute = @_isAttributeExisting(defaultAttribute, serverAttributes)
      if serverAttribute
        defaultAttribute.value = serverAttribute.value
    extendedAttributes.push(defaultAttribute)

  _isAttributeExisting: (defaultAttribute, attributeList) ->
    _.findWhere(attributeList, { name: "#{defaultAttribute.name}" })

module.exports = EnsureDefaultAttributes