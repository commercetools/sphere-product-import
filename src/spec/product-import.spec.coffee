_ = require 'underscore'
_.mixin require('underscore-mixins')
{ProductImport} = require '../coffee'
Config = require('../../config')
Promise = require 'bluebird'
fs = require 'fs'

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
        masterVariant: { sku: 'e' }
        variants: []
      }
    ]

sampleProductProjectionResponse = [
  {
    masterVariant : { sku: 'e'},
    variants: []
  }
]

sampleProductTypeResponse =
  body:
    results: [
      {
        "id": "product_type_internal_id",
        "version": 1,
        "name": "AGS",
        "description": "Gütesiegel",
        "classifier": "Complex",
        "attributes": [ ],
        "createdAt": "2015-04-15T15:11:07.175Z",
        "lastModifiedAt": "2015-04-15T15:11:07.175Z"
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

    it 'should extract 5 unique skus from master and variants', ->
      skus = @import._extractUniqueSkus(sampleProducts)
      expect(skus.length).toBe 5
      expect(skus).toEqual ['a', 'b', 'c', 'd', 'e']

  describe '::_prepareProductFetchBySkuQueryPredicate', ->

    it 'should return predicate with 5 unique skus', ->
      skus = @import._extractUniqueSkus(sampleProducts)
      predicate = @import._prepareProductFetchBySkuQueryPredicate(skus)
      expect(predicate).toEqual 'masterVariant(sku in ("a", "b", "c", "d", "e")) or variants(sku in ("a", "b", "c", "d", "e"))'

  describe '::_isExistingEntry', ->

    it 'should detect existing entries', ->
      existingProduct = sampleProducts[2]
      newProduct = sampleProducts[0]
      expect(@import._isExistingEntry(existingProduct,sampleProductProjectionResponse)).toBeDefined()
      expect(@import._isExistingEntry(existingProduct,sampleProductProjectionResponse).masterVariant.sku).toEqual "e"
      expect(@import._isExistingEntry(newProduct,sampleProductProjectionResponse)).toBeUndefined()

  describe '::_resolveReference', ->

    it 'should resolve product type reference and cache the result', (done) ->
      @import._resetCache()
      spyOn(@import.client.productTypes, "fetch").and.callFake => Promise.resolve(sampleProductTypeResponse)
      productTypeRef = { id: 'AGS'}
      @import._resolveReference(@import.client.productTypes, 'productType', productTypeRef, "name=\"#{productTypeRef.id}\"")
        .then (result) =>
          console.log("Entered")
          expect(result).toEqual sampleProductTypeResponse.body.results[0]
          console.log("Cached result: ")
          console.log(@import._cache.productType[productTypeRef.id])
          console.log(sampleProductTypeResponse.body.results[0])
          expect(@import._cache.productType["AGS"]).toEqual sampleProductTypeResponse.body.results[0]
          done()
          .catch (err) -> done(err)


