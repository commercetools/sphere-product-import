debug = require('debug')('sphere-product-import:unknown-attributes-filter')
_ = require 'underscore'
_.mixin require 'underscore-mixins'
Promise = require 'bluebird'

class UnknownAttributesFilter

  constructor: (@logger) ->
    debug "Unknown Attributes Filter initialized."

# get names of all attributes from product type
# generate new attributes array without the unknown attributes
# replace the filtered the array and return the product

  filterUnknownAttributes: (productType, product) =>
    new Promise (resolve) =>
      resolve() unless product.attributes
      attrNameList = _.pluck(productType, 'name')
      @_filterAttributes attrNameList, product.attributes
      .then (filteredAttributes) ->
        product.attributes = filteredAttributes
        resolve(product)

  _filterAttributes: (attrNameList, attributes) =>



  _isUnknownAttribute: (attribute, attrNameList) ->
    attribute.name in attrNameList