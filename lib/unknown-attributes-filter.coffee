debug = require('debug')('sphere-product-import:unknown-attributes-filter')
_ = require 'underscore'
_.mixin require 'underscore-mixins'
Promise = require 'bluebird'

class UnknownAttributesFilter

  constructor: (@logger) ->
    debug "Unknown Attributes Filter initialized."

  filter: (productType, product) =>
    new Promise (resolve) =>
      resolve() unless productType.attributes
      attrNameList = _.pluck(productType.attributes, 'name')
      Promise.all [
        @_filterVariantAttributes(product.masterVariant, attrNameList),
        Promise.map product.variants, (variant) =>
          @_filterVariantAttributes(variant, attrNameList)
        , {concurrency: 5}
      ]
      .spread (masterVariant, variants) ->
        resolve _.extend(product, { masterVariant, variants })

  _filterVariantAttributes: (variant, attrNameList) =>
    new Promise (resolve) =>
      resolve(variant) unless variant.attributes
      @_filterAttributes attrNameList, variant.attributes
      .then (filteredAttributes) ->
        variant.attributes = filteredAttributes
        resolve(variant)

  _filterAttributes: (attrNameList, attributes) =>
    new Promise (resolve) =>
      filteredAttributes = []
      for attribute in attributes
        if @_isKnownAttribute(attribute, attrNameList)
          filteredAttributes.push attribute
      resolve filteredAttributes

  _isKnownAttribute: (attribute, attrNameList) ->
    attribute.name in attrNameList

module.exports = UnknownAttributesFilter