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

  it ' :: should initialize', ->
    expect(@import).toBeDefined()

  it ' :: should filter unique objects from collection', ->
    uniqueCollection = @import.uniqueObjectFilter(sampleObjectCollection)
    expect(uniqueCollection).toEqual expectUniqueCollection

  it ' :: should detect an existing object in an array of objects', ->
    testObject =
      action: 'addPlainEnumValue'
      attributeName: 'sample-enum-attribute'
      value:
        key: 'enum-3-key'
        label: 'enum-3-key'

    expect(@import.isObjectPresentInArray(sampleObjectCollection, testObject)).toBeTruthy()
