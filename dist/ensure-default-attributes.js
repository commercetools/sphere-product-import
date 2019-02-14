var EnsureDefaultAttributes, Promise, _,
  bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; };

_ = require('underscore');

_.mixin(require('underscore-mixins'));

Promise = require('bluebird');

EnsureDefaultAttributes = (function() {
  function EnsureDefaultAttributes(logger, defaultAttributes1) {
    this.logger = logger;
    this.defaultAttributes = defaultAttributes1;
    this._ensureInVariant = bind(this._ensureInVariant, this);
    this.ensureDefaultAttributesInProduct = bind(this.ensureDefaultAttributesInProduct, this);
    this.logger.debug('Ensuring default attributes');
  }

  EnsureDefaultAttributes.prototype.ensureDefaultAttributesInProduct = function(product, productFromServer) {
    var masterVariant, updatedProduct, updatedVariants;
    updatedProduct = _.deepClone(product);
    if (productFromServer) {
      masterVariant = productFromServer.masterVariant;
    }
    updatedProduct.masterVariant = this._ensureInVariant(product.masterVariant, masterVariant);
    updatedVariants = _.map(product.variants, (function(_this) {
      return function(variant) {
        var serverVariant;
        if (productFromServer) {
          serverVariant = productFromServer.variants.filter(function(v) {
            return v.sku === variant.sku;
          })[0];
        }
        return _this._ensureInVariant(variant, serverVariant);
      };
    })(this));
    updatedProduct.variants = updatedVariants;
    return Promise.resolve(updatedProduct);
  };

  EnsureDefaultAttributes.prototype._ensureInVariant = function(variant, serverVariant) {
    var defaultAttribute, defaultAttributes, extendedAttributes, i, len, serverAttributes;
    defaultAttributes = _.deepClone(this.defaultAttributes);
    if (!variant.attributes) {
      return variant;
    }
    extendedAttributes = _.deepClone(variant.attributes);
    if (serverVariant) {
      serverAttributes = serverVariant.attributes;
    }
    for (i = 0, len = defaultAttributes.length; i < len; i++) {
      defaultAttribute = defaultAttributes[i];
      if (!this._isAttributeExisting(defaultAttribute, variant.attributes)) {
        this._updateAttribute(serverAttributes, defaultAttribute, extendedAttributes);
      }
    }
    variant.attributes = extendedAttributes;
    return variant;
  };

  EnsureDefaultAttributes.prototype._updateAttribute = function(serverAttributes, defaultAttribute, extendedAttributes) {
    var serverAttribute;
    if (serverAttributes) {
      serverAttribute = this._isAttributeExisting(defaultAttribute, serverAttributes);
      if (serverAttribute) {
        defaultAttribute.value = serverAttribute.value;
      }
    }
    return extendedAttributes.push(defaultAttribute);
  };

  EnsureDefaultAttributes.prototype._isAttributeExisting = function(defaultAttribute, attributeList) {
    return _.findWhere(attributeList, {
      name: "" + defaultAttribute.name
    });
  };

  return EnsureDefaultAttributes;

})();

module.exports = EnsureDefaultAttributes;
