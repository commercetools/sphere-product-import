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

sampleTaxCategoryResponse =
  body:
    results: [
      {
        "id": "tax_category_internal_id",
        "version": 5,
        "name": "defaultTax_AT",
        "description": "Steuer Österreich",
        "rates": [
          {
            "name": "20% MwSt",
            "amount": 0.2,
            "includedInPrice": true,
            "country": "AT",
            "id": "2CV8kXRE"
          }
        ],
        "createdAt": "2015-03-03T10:12:22.136Z",
        "lastModifiedAt": "2015-04-16T07:36:36.123Z"
      }
    ]

sampleCategoriesResponse1 =
  body:
    results: [
      {
        id: "category_internal_id1"
        version: 2
        name:
          de: "obst-gemuse1"
        ancestors: []
        externalId: "category_external_id1"
      }
    ]

sampleCategoriesResponse2 =
  body:
    results: [
      {
        id: "category_internal_id2"
        version: 1
        name:
          de: "obst-gemuse2"
        ancestors: []
        externalId: "category_external_id2"
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
      spyOn(@import.client.productTypes, "fetch").andCallFake => Promise.resolve(sampleProductTypeResponse)
      productTypeRef = { id: 'AGS'}
      @import._resolveReference(@import.client.productTypes, 'productType', productTypeRef, "name=\"#{productTypeRef.id}\"")
      .then (result) =>
        expect(@import.client.productTypes.fetch).toHaveBeenCalled()
        expect(result).toEqual sampleProductTypeResponse.body.results[0].id
        expect(@import._cache.productType["AGS"]).toEqual sampleProductTypeResponse.body.results[0].id
        done()
      .catch done

    it 'should resolve tax category reference and cache the result', (done) ->
      @import._resetCache()
      spyOn(@import.client.taxCategories, "fetch").andCallFake => Promise.resolve(sampleTaxCategoryResponse)
      taxCategoryRef = { id: 'defaultTax_AT' }
      @import._resolveReference(@import.client.taxCategories, 'taxCategory', taxCategoryRef, "name=\"#{taxCategoryRef.id}\"")
      .then (result) =>
        expect(@import.client.taxCategories.fetch).toHaveBeenCalled()
        expect(result).toEqual sampleTaxCategoryResponse.body.results[0].id
        expect(@import._cache.taxCategory["defaultTax_AT"]).toEqual sampleTaxCategoryResponse.body.results[0].id
        done()
      .catch done


    it 'should resolve list of category references and cache the result', (done) ->
      @import._resetCache()
      spyOn(@import.client.categories, "fetch").andCallFake => Promise.resolve(sampleCategoriesResponse1)
      categoryRef = { id: 'category_external_id1' }
      @import._resolveReference(@import.client.categories, 'categories', categoryRef, "externalId=\"#{categoryRef.id}\"")
      .then (result) =>
        expect(@import.client.categories.fetch).toHaveBeenCalled()
        expect(result).toEqual sampleCategoriesResponse1.body.results[0].id
        expect(@import._cache.categories["category_external_id1"]).toEqual sampleCategoriesResponse1.body.results[0].id
        done()
      .catch done


    it 'should resolve reference from cache', (done) ->
      @import._resetCache()
      @import._cache.taxCategory['defaultTax_AT'] = "tax_category_internal_id"
      spyOn(@import.client.taxCategories, "fetch").andCallFake => Promise.resolve(sampleTaxCategoryResponse)
      taxCategoryRef = { id: 'defaultTax_AT' }
      @import._resolveReference(@import.client.taxCategories, 'taxCategory', taxCategoryRef, "name=\"#{taxCategoryRef.id}\"")
      .then (result) =>
        expect(@import.client.taxCategories.fetch).not.toHaveBeenCalled()
        expect(result).toEqual sampleTaxCategoryResponse.body.results[0].id
        expect(result.isRejected).toBeUndefined()
        done()
      .catch done


    it 'should throw error on undefined reference', (done) ->
      @import._resolveReference(@import.client.taxCategories, 'taxCategory', undefined , "name=\"#{taxCategoryRef?.id}\"")
      .then done
      .catch (err) ->
        expect(err).toBe 'Missing taxCategory'
        done()


