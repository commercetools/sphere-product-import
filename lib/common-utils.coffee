debug = require('debug')('sphere-product-import-common-utils')
_ = require 'underscore'
_.mixin require 'underscore-mixins'

class CommonUtils

  constructor: (@logger) ->
    debug "Enum Validator initialized."


  uniqueObjectFilter: (objCollection) =>
    uniques = []
    _.each objCollection, (obj) =>
      if not @isObjectPresentInArray(uniques, obj) then uniques.push(obj)
    uniques


  isObjectPresentInArray: (array, object) ->
    _.find array, (element) -> _.isEqual(element, object)

module.exports = CommonUtils