debug = require('debug')('sphere-product-import:unknown-attributes-filter')
_ = require 'underscore'
_.mixin require 'underscore-mixins'
Promise = require 'bluebird'

# The attributes not defined in the productType will be filtered/removed from
# the received product variants.
class UnknownAttributesFilter

  constructor: (@logger) ->
    debug "Unknown Attributes Filter initialized."

  filter: (productType, product) =>
    if productType.attributes
      attrNameList = _.pluck(productType.attributes, 'name')
      Promise.all [
        @_filterVariantAttributes(product.masterVariant, attrNameList),
        Promise.map product.variants, (variant) =>
          @_filterVariantAttributes(variant, attrNameList)
        , {concurrency: 5}
      ]
      .spread (masterVariant, variants) ->
        Promise.resolve _.extend(product, { masterVariant, variants })
    else
      debug 'product type received without attributes, aborting attribute filter.'
      Promise.resolve()

  _filterVariantAttributes: (variant, attrNameList) =>
    if variant.attributes
      @_filterAttributes attrNameList, variant.attributes
      .then (filteredAttributes) ->
        variant.attributes = filteredAttributes
        Promise.resolve variant
    else
      debug "skipping variant filter: as variant without attributes: #{variant.sku}"
      Promise.resolve(variant)

  _filterAttributes: (attrNameList, attributes) =>
    filteredAttributes = []
    for attribute in attributes
      if @_isKnownAttribute(attribute, attrNameList)
        filteredAttributes.push attribute
    Promise.resolve filteredAttributes

  _isKnownAttribute: (attribute, attrNameList) ->
    attribute.name in attrNameList

module.exports = UnknownAttributesFilter