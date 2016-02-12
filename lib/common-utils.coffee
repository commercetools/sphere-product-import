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

  ###*
   * takes an array of sku chunks and returns an array of sku chunks
   * where each chunk fits inside the query
  ###
  _separateSkusChunksIntoSmallerChunks: (skusChunk, skus, queryLimit) ->
    # use two sku lists since we have to query for masterVariant and variant
    # with the same list of skus
    skuString = encodeURIComponent(
      "\"#{skusChunk.join('","')}\"\"#{skusChunk.join('","')}\""
    )
    whereQuery = "
      masterVariant(sku in ()) or variants(sku in ())
    "
    fixBytes = Buffer.byteLength(encodeURIComponent(whereQuery),'utf-8')
    availableSkuBytes = queryLimit - fixBytes

    if Buffer.byteLength(skuString,'utf-8') >= availableSkuBytes
      # split skus and retry
      return @_separateSkusChunksIntoSmallerChunks(
        skusChunk.slice(0, Math.round(skusChunk.length / 2)),
        skus,
        queryLimit
      )
    # the skusChunk is now small enough to fit in a query
    # now we split the skus array in chunks of the size of the skusChunk
    chunkSize = skusChunk.length
    iterations = Math.ceil(skus.length / chunkSize)
    chunks = []
    for i in [1..iterations]
      chunks.push(skus.slice(0, chunkSize))
      # remove chunk from skus
      skus = skus.slice(chunkSize)
    return chunks

module.exports = CommonUtils
