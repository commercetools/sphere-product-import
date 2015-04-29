{ProductImport} = require '../lib'

describe 'ProductImport', ->

  beforeEach ->
    @import = new ProductImport

  it 'should initialize', ->
    expect(@import).toBeDefined()