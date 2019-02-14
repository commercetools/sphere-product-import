var ProductExport, Promise, SphereClient, _, debug, slugify;

debug = require('debug')('sphere-product-export');

_ = require('underscore');

_.mixin(require('underscore-mixins'));

Promise = require('bluebird');

slugify = require('underscore.string/slugify');

SphereClient = require('sphere-node-sdk').SphereClient;

ProductExport = (function() {
  function ProductExport(logger, options) {
    this.logger = logger;
    if (options == null) {
      options = {};
    }
    this.client = new SphereClient(options);
  }

  ProductExport.prototype.processStream = function(cb) {
    return this.client.productProjections.staged(true).process(cb, {
      accumulate: false
    });
  };

  return ProductExport;

})();

module.exports = ProductExport;
