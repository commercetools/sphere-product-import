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
    present = false
    _.each array, (element) ->
      if _.isEqual(object, element)
        present = true
    present

module.exports = CommonUtils