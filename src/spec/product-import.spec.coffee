_ = require 'underscore'
_.mixin require('underscore-mixins')
{ProductImport} = require '../lib'
Config = require('../config')
Promise = require 'bluebird'
fs = require('fs')
#This should be done in beforeAll method.
sampleProducts = require('../samples/sampleimportproduct.json')

describe 'ProductImport', ->

  beforeEach ->
    @import = new ProductImport null, Config

  it 'should initialize', ->
    expect(@import).toBeDefined()
    expect(@import.client).toBeDefined()
    expect(@import.client.constructor.name).toBe 'SphereClient'
    expect(@import.sync).toBeDefined()
    expect(@import.sync.constructor.name).toBe 'ProductSync'


  describe '::_uniqueProductsBySku', ->

    it 'should filter duplicate skus', ->
      products = [{sku: 'foo'}, {sku: 'bar'}, {sku: 'baz'}, {sku: 'foo'}]
      uniqueProducts = @import._uniqueProductsBySku(products)
      expect(uniqueProducts.length).toBe 3
      expect(_.pluck(uniqueProducts, 'sku')).toEqual ['foo', 'bar', 'baz']


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