debug = require('debug')('sphere-product-import-common-utils')
_ = require 'underscore'
_.mixin require 'underscore-mixins'
packageJson = require './../package.json'

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
      masterVariant(sku IN ()) or variants(sku IN ())
    "
    fixBytes = Buffer.byteLength(encodeURIComponent(whereQuery),'utf-8')
    availableSkuBytes = queryLimit - fixBytes
    getBytesOfChunk = (chunk) ->
      chunk = chunk.map((sku) => JSON.stringify(sku))
      # use two sku lists since we have to query for masterVariant and variant
      # with the same list of skus
      skuString = encodeURIComponent("#{chunk}\"\"#{chunk}")
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

  # This assumes that the product always has update actions.
  canBePublished: (product, publishingStrategy) ->
    if publishingStrategy is 'always'
      return true
    else if publishingStrategy is 'stagedAndPublishedOnly'
      if product.hasStagedChanges is true and product.published is true then return true else return false
    else if publishingStrategy is 'notStagedAndPublishedOnly'
      if product.hasStagedChanges is false and product.published is true then return true else return false
    else
      @logger.warn 'unknown publishing strategy ' + publishingStrategy
      return false

  extendUserAgent: (clientConfig) ->
    userAgentPrefix = "#{packageJson.name}/#{packageJson.version}"

    if not clientConfig.user_agent
      clientConfig.user_agent = userAgentPrefix

    if not clientConfig.user_agent.startsWith(userAgentPrefix)
      clientConfig.user_agent = "#{userAgentPrefix} ( #{clientConfig.user_agent} )"

    clientConfig


module.exports = CommonUtils
