{ config, pkgs, lib, kubenix, ... }:

with lib;

let
  cfg = config.testing;
  parentConfig = config;
in {
  options = {
    testing.throwError = mkOption {
      description = "Whether to throw error";
      type = types.bool;
      default = true;
    };

    testing.defaults = mkOption {
      description = "Testing defaults";
      type = types.coercedTo types.unspecified (value: [value]) (types.listOf types.unspecified);
      example = literalExample ''{config, ...}: {
        kubernetes.version = config.kubernetes.version;
      }'';
      default = [];
    };

    testing.tests = mkOption {
      description = "Attribute set of test cases";
      default = [];
      type = types.listOf (types.coercedTo types.path (module: {inherit module;}) (types.submodule ({config, ...}: let
        modules = [config.module ./test.nix {
          config._module.args.test = config;
        }] ++ cfg.defaults;

        test = (kubenix.evalKubernetesModules {
          check = false;
          inherit modules;
        }).config.test;

        evaled =
          if test.enable
          then builtins.trace "testing ${test.name}" (kubenix.evalKubernetesModules {
            inherit modules;
          })
          else {success = false;};
      in {
        options = {
          name = mkOption {
            description = "test name";
            type = types.str;
            internal = true;
          };

          description = mkOption {
            description = "test description";
            type = types.str;
            internal = true;
          };

          enable = mkOption {
            description = "Whether to enable test";
            type = types.bool;
            internal = true;
          };

          module = mkOption {
            description = "Module defining submodule";
            type = types.unspecified;
          };

          evaled = mkOption {
            description = "Wheter test was evaled";
            type = types.bool;
            default =
              if cfg.throwError
              then if evaled.config.test.assertions != [] then true else true
              else (builtins.tryEval evaled.config.test.assertions).success;
            internal = true;
          };

          success = mkOption {
            description = "Whether test was success";
            type = types.bool;
            internal = true;
            default = false;
          };

          assertions = mkOption {
            description = "Test result";
            type = types.unspecified;
            internal = true;
            default = [];
          };
        };

        config = {
          inherit (test) name description enable;
          assertions = mkIf config.evaled evaled.config.test.assertions;
          success = mkIf config.evaled (all (el: el.assertion) config.assertions);
        };
      })));
      apply = tests: filter (test: test.enable) tests;
    };

    testing.success = mkOption {
      description = "Whether testing was a success";
      type = types.bool;
      default = all (test: test.success) cfg.tests;
    };

    testing.result = mkOption {
      description = "Testing result";
      type = types.package;
      default = pkgs.writeText "testing-report.json" (builtins.toJSON {
        success = cfg.success;
        tests = map (test: {
          inherit (test) name description evaled success;
          assertions = moduleToAttrs test.assertions;
        }) (filter (test: test.enable) cfg.tests);
      });
    };
  };
}
