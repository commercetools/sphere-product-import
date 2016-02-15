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
  _separateSkusChunksIntoSmallerChunks: (skus, queryLimit) ->
    whereQuery = "
      masterVariant(sku in ()) or variants(sku in ())
    "
    fixBytes = Buffer.byteLength(encodeURIComponent(whereQuery),'utf-8')
    availableSkuBytes = queryLimit - fixBytes
    getBytesOfChunk = (chunk) ->
      # use two sku lists since we have to query for masterVariant and variant
      # with the same list of skus
      skuString = encodeURIComponent(
        "\"#{chunk.join('","')}\"\"#{chunk.join('","')}\""
      )
      return Buffer.byteLength(skuString,'utf-8')
    # the skusChunk is now small enough to fit in a query
    # now we split the skus array in chunks of the size of the skusChunk
    chunks = _.reduce(skus, (chunks, sku) ->
      lastChunk = _.clone(_.last(chunks))
      lastChunk.push(sku)
      # if last chunk including the sku does not exceed, push to last chunk
      if getBytesOfChunk(lastChunk) < availableSkuBytes
        chunks.pop()
        chunks.push(lastChunk)
      else
        # otherwise open a new chunk
        chunks.push([ sku ])
      return chunks
    , [[]])
    return chunks

module.exports = CommonUtils
