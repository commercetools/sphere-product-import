_ = require 'underscore'
_.mixin require('underscore-mixins')
{ProductImport} = require '../lib'
Config = require('../config')
Promise = require 'bluebird'
fs = require('fs')
sampleProducts = require('../samples/import.json')
sampleProductProjectionsResponse = require('../samples/product_projection_response.json')

describe 'ProductImport', ->

  beforeEach ->
    @import = new ProductImport null, Config

  it 'should initialize', ->
    expect(@import).toBeDefined()
    expect(@import.client).toBeDefined()
    expect(@import.client.constructor.name).toBe 'SphereClient'
    expect(@import.sync).toBeDefined()
    expect(@import.sync.constructor.name).toBe 'ProductSync'


#  describe '::performStream', ->
#
#    it 'should execute callback after finished processing batches', (done) ->
#      spyOn(@import, '_processBatches').andCallFake -> Promise.resolve()
#      @import.performStream [1,2,3], done
#      .catch (err) -> done(_.prettify err)


  describe '::_extractUniqueSkus', ->

    it 'should extract 6 unique skus from master and variants', ->
      expect(sampleProducts.products.length).toBe 2
      skus = @import._extractUniqueSkus(sampleProducts.products)
      expect(skus.length).toBe 6
      expect(skus).toEqual ['B3-717597', 'B3-717487', 'B3-717489', 'C42-345678', 'C42-345987', 'C42-345988']

  describe '::_prepareProductFetchBySkuQueryPredicate', ->

    it 'should return predicate with 6 unique skus and of byte size 205', ->
      skus = @import._extractUniqueSkus(sampleProducts.products)
      predicate = @import._prepareProductFetchBySkuQueryPredicate(skus)
      expect(predicate.predicateString).toEqual 'masterVariant(sku in ("B3-717597", "B3-717487", "B3-717489", "C42-345678", "C42-345987", "C42-345988")) or variants(sku in ("B3-717597", "B3-717487", "B3-717489", "C42-345678", "C42-345987", "C42-345988"))'
      expect(predicate.byteSize).toBe 205

  describe '::_isExistingEntry', ->

    it 'should detect existing entries', ->
      existingProduct = sampleProducts.products[0]
      newProduct = sampleProducts.products[1]
      expect(@import._isExistingEntry(existingProduct,sampleProductProjectionsResponse.results)).toBeDefined()
      expect(@import._isExistingEntry(existingProduct,sampleProductProjectionsResponse.results).masterVariant.sku).toEqual "B3-717597"
      expect(@import._isExistingEntry(newProduct,sampleProductProjectionsResponse.results)).toBeUndefined()