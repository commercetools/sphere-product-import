_ = require 'underscore'
_.mixin require('underscore-mixins')
{ProductImport} = require '../lib'
Config = require('../config')
Promise = require 'bluebird'
fs = require 'fs'
sampleProductProjectionsResponse = require('../samples/product_projection_response.json')

sampleProducts = [
      {
        masterVariant: { sku: 'a' }
        variants: [
          { id: 2, sku: 'b' },
          { id: 3 },
          { id: 4, sku: 'c' },
        ]
      },
      {
        masterVariant: {}
        variants: [
          { id: 2, sku: 'b' },
          { id: 3, sku: 'd' },
        ]
      },
      {
        masterVariant: { sku: 'd' }
        variants: []
      }
    ]



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

    it 'should extract 4 unique skus from master and variants', ->
      skus = @import._extractUniqueSkus(sampleProducts)
      console.log(skus)
      expect(skus.length).toBe 4
      expect(skus).toEqual ['a', 'b', 'c', 'd']

  describe '::_prepareProductFetchBySkuQueryPredicate', ->

    it 'should return predicate with 6 unique skus', ->
      skus = @import._extractUniqueSkus(sampleProducts)
      predicate = @import._prepareProductFetchBySkuQueryPredicate(skus)
      expect(predicate).toEqual 'masterVariant(sku in ("a", "b", "c", "d")) or variants(sku in ("a", "b", "c", "d"))'

  describe '::_isExistingEntry', ->

    it 'should detect existing entries', ->
      existingProduct = sampleProducts.products[0]
      newProduct = sampleProducts.products[1]
      expect(@import._isExistingEntry(existingProduct,sampleProductProjectionsResponse.results)).toBeDefined()
      expect(@import._isExistingEntry(existingProduct,sampleProductProjectionsResponse.results).masterVariant.sku).toEqual "B3-717597"
      expect(@import._isExistingEntry(newProduct,sampleProductProjectionsResponse.results)).toBeUndefined()