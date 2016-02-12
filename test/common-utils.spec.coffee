debug = require('debug')('spec:common-utils')
_ = require 'underscore'
_.mixin require 'underscore-mixins'
{CommonUtils} = require '../lib'
{ExtendedLogger} = require 'sphere-node-utils'
package_json = require '../package.json'

sampleObjectCollection = [
  action: 'addPlainEnumValue'
  attributeName: 'sample-enum-attribute'
  value:
    key: 'enum-3-key'
    label: 'enum-3-key'
,
  action: 'addPlainEnumValue'
  attributeName: 'sample-enum-attribute'
  value:
    key: 'enum-1-key'
    label: 'enum-1-key'
,
  action: 'addPlainEnumValue'
  attributeName: 'sample-enum-attribute'
  value:
    key: 'enum-3-key'
    label: 'enum-3-key'
]

expectUniqueCollection = [
  action: 'addPlainEnumValue'
  attributeName: 'sample-enum-attribute'
  value:
    key: 'enum-3-key'
    label: 'enum-3-key'
,
  action: 'addPlainEnumValue'
  attributeName: 'sample-enum-attribute'
  value:
    key: 'enum-1-key'
    label: 'enum-1-key'
]

describe 'Common Utils unit tests', ->

  beforeEach ->
    @logger = new ExtendedLogger
      additionalFields:
        project_key: 'enumValidator'
      logConfig:
        name: "#{package_json.name}-#{package_json.version}"
        streams: [
          { level: 'info', stream: process.stdout }
        ]

    @import = new CommonUtils @logger

  it ' should initialize', ->
    expect(@import).toBeDefined()

  it ' should filter unique objects from collection', ->
    uniqueCollection = @import.uniqueObjectFilter(sampleObjectCollection)
    expect(uniqueCollection).toEqual expectUniqueCollection

  it ' should detect an existing object in an array of objects', ->
    testObject =
      action: 'addPlainEnumValue'
      attributeName: 'sample-enum-attribute'
      value:
        key: 'enum-3-key'
        label: 'enum-3-key'

    expect(@import.isObjectPresentInArray(sampleObjectCollection, testObject)).toBeTruthy()

  describe '::_separateSkusChunksIntoSmallerChunks', ->

    it 'should split a list of skus that is to big for a single query
    into chunks that are small enough for a query', ->
      # 3 bytes string
      sku = 'SKU'
      skus = []
      for i in [1..10000]
        skus.push(sku)
      # skus is now a 30000 bytes
      chunks = @import._separateSkusChunksIntoSmallerChunks(skus, skus, 8073)
      # the number of chunks should be at least the number of actual bytes
      # divided by the number of maximum bytes per request
      expect(chunks.length).toBeGreaterThan(30000 / 8072)
      # check chunk byte sizes
      _.each(chunks, (chunk) ->
        skuStr = chunk.join(',')
        queryStr = "
          masterVariant(sku in (#{skuStr})) or variants(sku in (#{skuStr}))
        "
        actual = Buffer.byteLength(encodeURIComponent(queryStr), 'utf-8')
        expected = 8073
        # expect to be max 8072 bytes
        expect(actual).toBeLessThan(expected)
      )
