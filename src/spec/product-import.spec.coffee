{ProductImport} = require '../lib'
Config = require('../config')

describe 'ProductImport', ->

  beforeEach ->
    @import = new ProductImport null, Config

  it 'should initialize', ->
    expect(@import).toBeDefined()