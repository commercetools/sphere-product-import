var Promise, UnknownAttributesFilter, _, debug,
  bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; },
  indexOf = [].indexOf || function(item) { for (var i = 0, l = this.length; i < l; i++) { if (i in this && this[i] === item) return i; } return -1; };

debug = require('debug')('sphere-product-import:unknown-attributes-filter');

_ = require('underscore');

_.mixin(require('underscore-mixins'));

Promise = require('bluebird');

UnknownAttributesFilter = (function() {
  function UnknownAttributesFilter(logger) {
    this.logger = logger;
    this._unknownAttributeNameCollector = bind(this._unknownAttributeNameCollector, this);
    this._filterAttributes = bind(this._filterAttributes, this);
    this._filterVariantAttributes = bind(this._filterVariantAttributes, this);
    this.filter = bind(this.filter, this);
    debug("Unknown Attributes Filter initialized.");
  }

  UnknownAttributesFilter.prototype.filter = function(productType, product, collectedUnknownAttributeNames) {
    var attrNameList;
    this.collectedUnknownAttributeNames = collectedUnknownAttributeNames;
    if (productType.attributes) {
      attrNameList = _.pluck(productType.attributes, 'name');
      return Promise.all([
        this._filterVariantAttributes(product.masterVariant, attrNameList), Promise.map(product.variants, (function(_this) {
          return function(variant) {
            return _this._filterVariantAttributes(variant, attrNameList);
          };
        })(this), {
          concurrency: 5
        })
      ]).spread(function(masterVariant, variants) {
        return Promise.resolve(_.extend(product, {
          masterVariant: masterVariant,
          variants: variants
        }));
      });
    } else {
      debug('product type received without attributes, aborting attribute filter.');
      return Promise.resolve();
    }
  };

  UnknownAttributesFilter.prototype._filterVariantAttributes = function(variant, attrNameList) {
    if (variant.attributes) {
      return this._filterAttributes(attrNameList, variant.attributes).then(function(filteredAttributes) {
        variant.attributes = filteredAttributes;
        return Promise.resolve(variant);
      });
    } else {
      debug("skipping variant filter: as variant without attributes: " + variant.sku);
      return Promise.resolve(variant);
    }
  };

  UnknownAttributesFilter.prototype._filterAttributes = function(attrNameList, attributes) {
    var attribute, filteredAttributes, i, len;
    filteredAttributes = [];
    for (i = 0, len = attributes.length; i < len; i++) {
      attribute = attributes[i];
      if (this._isKnownAttribute(attribute, attrNameList)) {
        filteredAttributes.push(attribute);
      } else if (this.collectedUnknownAttributeNames) {
        this._unknownAttributeNameCollector(attribute.name);
      }
    }
    return Promise.resolve(filteredAttributes);
  };

  UnknownAttributesFilter.prototype._isKnownAttribute = function(attribute, attrNameList) {
    var ref;
    return ref = attribute.name, indexOf.call(attrNameList, ref) >= 0;
  };

  UnknownAttributesFilter.prototype._unknownAttributeNameCollector = function(attributeName) {
    if (!_.contains(this.collectedUnknownAttributeNames, attributeName)) {
      return this.collectedUnknownAttributeNames.push(attributeName);
    }
  };

  return UnknownAttributesFilter;

})();

module.exports = UnknownAttributesFilter;
