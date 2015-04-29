![SPHERE.IO icon](https://admin.sphere.io/assets/images/sphere_logo_rgb_long.png)

# Stock import

[![NPM](https://nodei.co/npm/sphere-stock-import.png?downloads=true)](https://www.npmjs.org/package/sphere-stock-import)

[![Build Status](https://secure.travis-ci.org/sphereio/sphere-stock-import.png?branch=master)](http://travis-ci.org/sphereio/sphere-stock-import) [![NPM version](https://badge.fury.io/js/sphere-stock-import.png)](http://badge.fury.io/js/sphere-stock-import) [![Coverage Status](https://coveralls.io/repos/sphereio/sphere-stock-import/badge.png)](https://coveralls.io/r/sphereio/sphere-stock-import) [![Dependency Status](https://david-dm.org/sphereio/sphere-stock-import.png?theme=shields.io)](https://david-dm.org/sphereio/sphere-stock-import) [![devDependency Status](https://david-dm.org/sphereio/sphere-stock-import/dev-status.png?theme=shields.io)](https://david-dm.org/sphereio/sphere-stock-import#info=devDependencies)

This module allows to import stock information from CSV and XML files, with SFTP support.

## Getting started

```bash
$ npm install -g sphere-stock-import

# output help screen
$ stock-import
```

### SFTP
By default you need to specify the path to a local file in order to read the import information, via the `--file` option.

When using SFTP, you should not use the `--file` option, instead you need to provide at least the required `--sftp*` options:
- `--sftpCredentials` (or `--sftpHost`, `--sftpUsername`, `--sftpPassword`)
- `--sftpSource`
- `--sftpTarget`


### CSV Format

Column 1 will be used as `SKU` identifier, whereas column 2 will be used as `quantity`.
An example:
```
sku,quantity
foo,9
bar,-1
SKU-123,42
```

> Please note that the header names are currently ignored.

### XML Format

```xml
<?xml version="1.0" encoding="UTF-8"?>
<root>
  <row>
    <code>foo</code>
    <quantity>7</quantity>
  </row>
  <row>
    <code>bar</code>
    <quantity>1</quantity>
  </row>
</root>
```

## Contributing
In lieu of a formal styleguide, take care to maintain the existing coding style. Add unit tests for any new or changed functionality. Lint and test your code using [Grunt](http://gruntjs.com/).
More info [here](CONTRIBUTING.md)

## Releasing
Releasing a new version is completely automated using the Grunt task `grunt release`.

```javascript
grunt release // patch release
grunt release:minor // minor release
grunt release:major // major release
```

## License
Copyright (c) 2014 SPHERE.IO
Licensed under the [MIT license](LICENSE-MIT).
