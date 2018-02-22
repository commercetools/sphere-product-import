var CommonUtils, _, debug,
  bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; };

debug = require('debug')('sphere-product-import-common-utils');

_ = require('underscore');

_.mixin(require('underscore-mixins'));

CommonUtils = (function() {
  function CommonUtils(logger) {
    this.logger = logger;
    this.uniqueObjectFilter = bind(this.uniqueObjectFilter, this);
    debug("Enum Validator initialized.");
  }

  CommonUtils.prototype.uniqueObjectFilter = function(objCollection) {
    var uniques;
    uniques = [];
    _.each(objCollection, (function(_this) {
      return function(obj) {
        if (!_this.isObjectPresentInArray(uniques, obj)) {
          return uniques.push(obj);
        }
      };
    })(this));
    return uniques;
  };

  CommonUtils.prototype.isObjectPresentInArray = function(array, object) {
    return _.find(array, function(element) {
      return _.isEqual(element, object);
    });
  };


  /**
   * takes an array of sku chunks and returns an array of sku chunks
   * where each chunk fits inside the query
   */

  CommonUtils.prototype._separateSkusChunksIntoSmallerChunks = function(skus, queryLimit) {
    var availableSkuBytes, chunks, fixBytes, getBytesOfChunk, whereQuery;
    whereQuery = "masterVariant(sku in ()) or variants(sku in ())";
    fixBytes = Buffer.byteLength(encodeURIComponent(whereQuery), 'utf-8');
    availableSkuBytes = queryLimit - fixBytes;
    getBytesOfChunk = function(chunk) {
      var skuString;
      skuString = encodeURIComponent("\"" + (chunk.join('","')) + "\"\"" + (chunk.join('","')) + "\"");
      return Buffer.byteLength(skuString, 'utf-8');
    };
    chunks = _.reduce(skus, function(chunks, sku) {
      var lastChunk;
      lastChunk = _.clone(_.last(chunks));
      lastChunk.push(sku);
      if (getBytesOfChunk(lastChunk) < availableSkuBytes) {
        chunks.pop();
        chunks.push(lastChunk);
      } else {
        chunks.push([sku]);
      }
      return chunks;
    }, [[]]);
    return chunks;
  };

  CommonUtils.prototype.canBePublished = function(product, publishingStrategy) {
    if (publishingStrategy === 'always') {
      return true;
    } else if (publishingStrategy === 'stagedAndPublishedOnly') {
      if (product.hasStagedChanges === true && product.published === true) {
        return true;
      } else {
        return false;
      }
    } else if (publishingStrategy === 'notStagedAndPublishedOnly') {
      if (product.hasStagedChanges === false && product.published === true) {
        return true;
      } else {
        return false;
      }
    } else {
      this.logger.warn('unknown publishing strategy ' + publishingStrategy);
      return false;
    }
  };

  return CommonUtils;

})();

module.exports = CommonUtils;
