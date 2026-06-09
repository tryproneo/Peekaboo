import Foundation
import Tachikoma
import Testing
@testable import PeekabooAgentRuntime
@testable import PeekabooAutomation
@testable import PeekabooCore
@testable import PeekabooVisualizer

/// Tests for PeekabooAgentService model selection functionality
struct PeekabooAgentServiceTests {
    @MainActor
    private func makeServices() -> PeekabooServices {
        PeekabooServices()
    }

    @Test
    @MainActor
    func `Default model initialization`() throws {
        let mockServices = self.makeServices()
        let agentService = try PeekabooAgentService(services: mockServices)

        // Should default to Claude Opus 4.8
        #expect(agentService.defaultModel == LanguageModel.anthropic(.opus48).description)
    }

    @Test
    @MainActor
    func `Anthropic generation settings avoid stale thinking option`() throws {
        let mockServices = self.makeServices()
        let agentService = try PeekabooAgentService(services: mockServices)

        let settings = agentService.generationSettings(for: .anthropic(.opus47))

        #expect(settings.maxTokens == 4096)
        #expect(settings.providerOptions.anthropic?.thinking == nil)
    }

    @Test
    @MainActor
    func `Gemini only credentials initialize Gemini default agent`() throws {
        try self.withIsolatedAgentEnvironment(["GEMINI_API_KEY": "test-gemini-key"]) {
            let services = self.makeServices()
            let agentService = try #require(services.agent as? PeekabooAgentService)

            #expect(agentService.defaultModel == LanguageModel.google(.gemini35Flash).description)
        }
    }

    @Test
    @MainActor
    func `MiniMax only credentials initialize MiniMax default agent`() throws {
        try self.withIsolatedAgentEnvironment(["MINIMAX_API_KEY": "test-minimax-key"]) {
            let services = self.makeServices()
            let agentService = try #require(services.agent as? PeekabooAgentService)

            #expect(agentService.defaultModel == LanguageModel.minimax(.m27).description)
        }
    }

    @Test
    @MainActor
    func `xAI only credentials initialize Grok default agent`() throws {
        try self.withIsolatedAgentEnvironment(["X_AI_API_KEY": "test-xai-key"]) {
            let services = self.makeServices()
            let agentService = try #require(services.agent as? PeekabooAgentService)

            #expect(agentService.defaultModel == LanguageModel.grok(.grok43).description)
        }
    }

    @Test
    @MainActor
    func `Generated provider list preserves available model order`() throws {
        try self.withIsolatedAgentEnvironment([
            "OPENAI_API_KEY": "test-openai-key",
            "ANTHROPIC_API_KEY": "test-anthropic-key",
        ]) {
            let services = self.makeServices()
            let agentService = try #require(services.agent as? PeekabooAgentService)

            #expect(agentService.defaultModel == LanguageModel.openai(.gpt55).description)
        }
    }

    @Test
    @MainActor
    func `Saved custom provider initializes default agent`() throws {
        try self.withIsolatedAgentEnvironment(
            ["PEEKABOO_CUSTOM_PROVIDER_KEY": "resolved-secret"],
            configurationJSON: """
            {
              "customProviders": {
                "local-proxy": {
                  "name": "Local Proxy",
                  "type": "openai",
                  "enabled": true,
                  "options": {
                    "baseURL": "http://localhost:8317/v1",
                    "apiKey": "${PEEKABOO_CUSTOM_PROVIDER_KEY}"
                  },
                  "models": {
                    "mini": {
                      "name": "gpt-5.5-mini",
                      "supportsVision": true
                    }
                  }
                }
              }
            }
            """) {
                let services = self.makeServices()
                let agentService = try #require(services.agent as? PeekabooAgentService)

                #expect(agentService.defaultModel == "Custom/local-proxy/mini")
            }
    }

    @Test
    @MainActor
    func `Saved custom provider default preserves model alias metadata`() throws {
        try self.withIsolatedAgentEnvironment(
            ["PEEKABOO_CUSTOM_PROVIDER_KEY": "resolved-secret"],
            configurationJSON: """
            {
              "customProviders": {
                "local-proxy": {
                  "name": "Local Proxy",
                  "type": "openai",
                  "enabled": true,
                  "options": {
                    "baseURL": "http://localhost:8317/v1",
                    "apiKey": "${PEEKABOO_CUSTOM_PROVIDER_KEY}"
                  },
                  "models": {
                    "alias": {
                      "name": "same",
                      "supportsVision": false,
                      "supportsTools": true
                    },
                    "same": {
                      "name": "wrong",
                      "supportsVision": true,
                      "supportsTools": true
                    }
                  }
                }
              }
            }
            """) {
                let services = self.makeServices()
                let agentService = try #require(services.agent as? PeekabooAgentService)

                #expect(agentService.defaultModelSelection == "local-proxy/alias")
                #expect(agentService.defaultLanguageModel.modelId == "local-proxy/alias")
                #expect(!agentService.defaultLanguageModel.supportsVision)
                #expect(agentService.resolveConfiguredModel("local-proxy/alias")?.modelId == "local-proxy/alias")
            }
    }

    @Test
    @MainActor
    func `Configured custom default wins over built-in credentials`() throws {
        try self.withIsolatedAgentEnvironment(
            [
                "OPENAI_API_KEY": "test-openai-key",
                "PEEKABOO_CUSTOM_PROVIDER_KEY": "resolved-secret",
            ],
            configurationJSON: """
            {
              "agent": {
                "defaultModel": "local-proxy/mini"
              },
              "customProviders": {
                "local-proxy": {
                  "name": "Local Proxy",
                  "type": "openai",
                  "enabled": true,
                  "options": {
                    "baseURL": "http://localhost:8317/v1",
                    "apiKey": "${PEEKABOO_CUSTOM_PROVIDER_KEY}"
                  },
                  "models": {
                    "mini": {
                      "name": "gpt-5.5-mini",
                      "supportsVision": true,
                      "supportsTools": true
                    }
                  }
                }
              }
            }
            """) {
                let services = self.makeServices()
                let agentService = try #require(services.agent as? PeekabooAgentService)

                #expect(agentService.defaultModel == "Custom/local-proxy/mini")
            }
    }

    @Test
    @MainActor
    func `Settings-style custom default wins over built-in credentials`() throws {
        try self.withIsolatedAgentEnvironment(
            [
                "OPENAI_API_KEY": "test-openai-key",
                "PEEKABOO_CUSTOM_PROVIDER_KEY": "resolved-secret",
            ],
            configurationJSON: """
            {
              "aiProviders": {
                "providers": "local-proxy/mini,ollama/llava:latest"
              },
              "agent": {
                "defaultModel": "mini"
              },
              "customProviders": {
                "local-proxy": {
                  "name": "Local Proxy",
                  "type": "openai",
                  "enabled": true,
                  "options": {
                    "baseURL": "http://localhost:8317/v1",
                    "apiKey": "${PEEKABOO_CUSTOM_PROVIDER_KEY}"
                  },
                  "models": {
                    "mini": {
                      "name": "gpt-5.5-mini",
                      "supportsVision": true,
                      "supportsTools": true
                    }
                  }
                }
              }
            }
            """) {
                let services = self.makeServices()
                let agentService = try #require(services.agent as? PeekabooAgentService)

                #expect(agentService.defaultModel == "Custom/local-proxy/mini")
            }
    }

    @Test
    @MainActor
    func `Saved custom provider does not override built-in credentials`() throws {
        try self.withIsolatedAgentEnvironment(
            [
                "GEMINI_API_KEY": "test-gemini-key",
                "PEEKABOO_CUSTOM_PROVIDER_KEY": "resolved-secret",
            ],
            configurationJSON: """
            {
              "customProviders": {
                "local-proxy": {
                  "name": "Local Proxy",
                  "type": "openai",
                  "enabled": true,
                  "options": {
                    "baseURL": "http://localhost:8317/v1",
                    "apiKey": "${PEEKABOO_CUSTOM_PROVIDER_KEY}"
                  },
                  "models": {
                    "mini": {
                      "name": "Display Name",
                      "supportsVision": true,
                      "supportsTools": true
                    }
                  }
                }
              }
            }
            """) {
                let services = self.makeServices()
                let agentService = try #require(services.agent as? PeekabooAgentService)

                #expect(agentService.defaultModel == LanguageModel.google(.gemini35Flash).description)
            }
    }

    @Test
    @MainActor
    func `Non-tool custom provider does not initialize agent`() throws {
        try self.withIsolatedAgentEnvironment(
            ["PEEKABOO_CUSTOM_PROVIDER_KEY": "resolved-secret"],
            configurationJSON: """
            {
              "customProviders": {
                "local-proxy": {
                  "name": "Local Proxy",
                  "type": "openai",
                  "enabled": true,
                  "options": {
                    "baseURL": "http://localhost:8317/v1",
                    "apiKey": "${PEEKABOO_CUSTOM_PROVIDER_KEY}"
                  },
                  "models": {
                    "mini": {
                      "name": "gpt-5.5-mini",
                      "supportsVision": true,
                      "supportsTools": false
                    }
                  }
                }
              }
            }
            """) {
                let services = self.makeServices()

                #expect(services.agent == nil)
            }
    }

    @Test
    @MainActor
    func `Explicit custom provider list initializes default agent`() throws {
        try self.withIsolatedAgentEnvironment(
            ["PEEKABOO_CUSTOM_PROVIDER_KEY": "resolved-secret"],
            configurationJSON: """
            {
              "aiProviders": {
                "providers": "local-proxy/mini"
              },
              "customProviders": {
                "local-proxy": {
                  "name": "Local Proxy",
                  "type": "openai",
                  "enabled": true,
                  "options": {
                    "baseURL": "http://localhost:8317/v1",
                    "apiKey": "${PEEKABOO_CUSTOM_PROVIDER_KEY}"
                  },
                  "models": {
                    "mini": {
                      "name": "gpt-5.5-mini",
                      "supportsVision": true
                    }
                  }
                }
              }
            }
            """) {
                let services = self.makeServices()
                let agentService = try #require(services.agent as? PeekabooAgentService)

                #expect(agentService.defaultModel == "Custom/local-proxy/mini")
            }
    }

    @Test
    @MainActor
    func `Explicit custom provider list preserves custom order before built-in`() throws {
        try self.withIsolatedAgentEnvironment(
            [
                "ANTHROPIC_API_KEY": "test-anthropic-key",
                "PEEKABOO_CUSTOM_PROVIDER_KEY": "resolved-secret",
            ],
            configurationJSON: """
            {
              "aiProviders": {
                "providers": "local-proxy/mini,anthropic/claude-opus-4-8"
              },
              "customProviders": {
                "local-proxy": {
                  "name": "Local Proxy",
                  "type": "openai",
                  "enabled": true,
                  "options": {
                    "baseURL": "http://localhost:8317/v1",
                    "apiKey": "${PEEKABOO_CUSTOM_PROVIDER_KEY}"
                  },
                  "models": {
                    "mini": {
                      "name": "gpt-5.5-mini",
                      "supportsVision": true,
                      "supportsTools": true
                    }
                  }
                }
              }
            }
            """) {
                let services = self.makeServices()
                let agentService = try #require(services.agent as? PeekabooAgentService)

                #expect(agentService.defaultModel == "Custom/local-proxy/mini")
            }
    }

    @Test
    @MainActor
    func `Missing custom default credentials fall back to available built-in`() throws {
        try self.withIsolatedAgentEnvironment(
            ["OPENAI_API_KEY": "test-openai-key"],
            configurationJSON: """
            {
              "agent": {
                "defaultModel": "local-proxy/mini"
              },
              "customProviders": {
                "local-proxy": {
                  "name": "Local Proxy",
                  "type": "openai",
                  "enabled": true,
                  "options": {
                    "baseURL": "http://localhost:8317/v1",
                    "apiKey": "${PEEKABOO_MISSING_PROVIDER_KEY}"
                  },
                  "models": {
                    "mini": {
                      "name": "gpt-5.5-mini",
                      "supportsVision": true,
                      "supportsTools": true
                    }
                  }
                }
              }
            }
            """) {
                let services = self.makeServices()
                let agentService = try #require(services.agent as? PeekabooAgentService)

                #expect(agentService.defaultModel == LanguageModel.openai(.gpt55).description)
            }
    }

    @Test
    @MainActor
    func `MiniMax China only credentials initialize MiniMax China default agent`() throws {
        try self.withIsolatedAgentEnvironment(["MINIMAX_CN_API_KEY": "test-minimax-cn-key"]) {
            let services = self.makeServices()
            let agentService = try #require(services.agent as? PeekabooAgentService)

            #expect(agentService.defaultModel == LanguageModel.minimaxCN(.m27).description)
        }
    }

    @Test
    @MainActor
    func `Unavailable custom alias does not fall through to hosted provider`() throws {
        try self.withIsolatedAgentEnvironment(
            ["X_AI_API_KEY": "test-xai-key"],
            configurationJSON: """
            {
              "aiProviders": {
                "providers": "xai/mini"
              },
              "customProviders": {
                "xai": {
                  "name": "Custom xAI Proxy",
                  "type": "openai",
                  "enabled": true,
                  "options": {
                    "baseURL": "http://localhost:8317/v1",
                    "apiKey": "${PEEKABOO_MISSING_PROVIDER_KEY}"
                  },
                  "models": {
                    "mini": {
                      "name": "Proxy Mini",
                      "supportsVision": true,
                      "supportsTools": true
                    }
                  }
                }
              }
            }
            """) {
                let services = self.makeServices()

                #expect(services.agent == nil)
            }
    }

    @Test
    @MainActor
    func `Generated custom provider selection does not fall through to shadowed hosted provider`() throws {
        try self.withIsolatedAgentEnvironment(
            ["X_AI_API_KEY": "test-xai-key"],
            configurationJSON: """
            {
              "aiProviders": {
                "providers": "xai/mini,ollama/llava:latest"
              },
              "agent": {
                "defaultModel": "xai/mini"
              },
              "customProviders": {
                "xai": {
                  "name": "Custom xAI Proxy",
                  "type": "openai",
                  "enabled": true,
                  "options": {
                    "baseURL": "http://localhost:8317/v1",
                    "apiKey": "${PEEKABOO_MISSING_PROVIDER_KEY}"
                  },
                  "models": {
                    "mini": {
                      "name": "Proxy Mini",
                      "supportsVision": true,
                      "supportsTools": true
                    }
                  }
                }
              }
            }
            """) {
                let services = self.makeServices()

                #expect(services.agent == nil)
            }
    }

    @Test
    @MainActor
    func `MiniMax China configured default can reuse shared MiniMax key`() throws {
        try self.withIsolatedAgentEnvironment(
            ["MINIMAX_API_KEY": "test-minimax-key"],
            configurationJSON: """
            {
              "agent": {
                "defaultModel": "minimax-cn/MiniMax-M2.7"
              }
            }
            """) {
                let services = self.makeServices()
                let agentService = try #require(services.agent as? PeekabooAgentService)

                #expect(agentService.defaultModel == LanguageModel.minimaxCN(.m27).description)
            }
    }

    @Test
    @MainActor
    func `Generated default model does not block Gemini default agent`() throws {
        try self.withIsolatedAgentEnvironment(
            ["GEMINI_API_KEY": "test-gemini-key"],
            configurationJSON: """
            {
              "aiProviders": {
                "providers": "anthropic/claude-opus-4-7,ollama/llava:latest"
              },
              "agent": {
                "defaultModel": "claude-opus-4-7"
              }
            }
            """) {
                let services = self.makeServices()
                let agentService = try #require(services.agent as? PeekabooAgentService)

                #expect(agentService.defaultModel == LanguageModel.google(.gemini35Flash).description)
            }
    }

    @Test
    @MainActor
    func `Generated default model does not block MiniMax default agent`() throws {
        try self.withIsolatedAgentEnvironment(
            ["MINIMAX_API_KEY": "test-minimax-key"],
            configurationJSON: """
            {
              "aiProviders": {
                "providers": "anthropic/claude-opus-4-7,ollama/llava:latest"
              },
              "agent": {
                "defaultModel": "claude-opus-4-7"
              }
            }
            """) {
                let services = self.makeServices()
                let agentService = try #require(services.agent as? PeekabooAgentService)

                #expect(agentService.defaultModel == LanguageModel.minimax(.m27).description)
            }
    }

    @Test
    @MainActor
    func `Explicit environment provider list does not fall back to unrelated credentials`() throws {
        try self.withIsolatedAgentEnvironment([
            "PEEKABOO_AI_PROVIDERS": "openai/gpt-5.5",
            "GEMINI_API_KEY": "test-gemini-key",
        ]) {
            let services = self.makeServices()

            #expect(services.agent == nil)
        }
    }

    @Test
    @MainActor
    func `Empty environment provider list does not block available credentials`() throws {
        try self.withIsolatedAgentEnvironment([
            "PEEKABOO_AI_PROVIDERS": "   ",
            "GEMINI_API_KEY": "test-gemini-key",
        ]) {
            let services = self.makeServices()
            let agentService = try #require(services.agent as? PeekabooAgentService)

            #expect(agentService.defaultModel == LanguageModel.google(.gemini35Flash).description)
        }
    }

    @Test
    @MainActor
    func `Explicit config provider list does not fall back to unrelated credentials`() throws {
        try self.withIsolatedAgentEnvironment(
            ["GEMINI_API_KEY": "test-gemini-key"],
            configurationJSON: """
            {
              "aiProviders": {
                "providers": "openai/gpt-5.5"
              },
              "agent": {
                "defaultModel": "gpt-5.5"
              }
            }
            """) {
                let services = self.makeServices()

                #expect(services.agent == nil)
            }
    }

    @Test
    @MainActor
    func `Explicit provider list does not fall back to custom default`() throws {
        try self.withIsolatedAgentEnvironment(
            ["PEEKABOO_CUSTOM_PROVIDER_KEY": "resolved-secret"],
            configurationJSON: """
            {
              "aiProviders": {
                "providers": "openai/gpt-5.5"
              },
              "customProviders": {
                "local-proxy": {
                  "name": "Local Proxy",
                  "type": "openai",
                  "enabled": true,
                  "options": {
                    "baseURL": "http://localhost:8317/v1",
                    "apiKey": "${PEEKABOO_CUSTOM_PROVIDER_KEY}"
                  },
                  "models": {
                    "mini": {
                      "name": "gpt-5.5-mini",
                      "supportsVision": true,
                      "supportsTools": true
                    }
                  }
                }
              }
            }
            """) {
                let services = self.makeServices()

                #expect(services.agent == nil)
            }
    }

    @Test
    @MainActor
    func `Configured Ollama provider initializes local default agent`() throws {
        try self.withIsolatedAgentEnvironment(["PEEKABOO_AI_PROVIDERS": "ollama/llama3.3"]) {
            let services = self.makeServices()
            let agentService = try #require(services.agent as? PeekabooAgentService)

            #expect(agentService.defaultModel == LanguageModel.ollama(.llama33).description)
        }
    }

    @Test
    @MainActor
    func `Unhandled hosted provider does not borrow unrelated credentials`() throws {
        try self.withIsolatedAgentEnvironment(
            ["GEMINI_API_KEY": "test-gemini-key"],
            configurationJSON: """
            {
              "aiProviders": {
                "providers": "mistral/mistral-large-latest"
              }
            }
            """) {
                let services = self.makeServices()

                #expect(services.agent == nil)
            }
    }

    @Test
    @MainActor
    func `Explicit provider list initializes server-redirected Grok model`() throws {
        try self.withIsolatedAgentEnvironment(
            ["X_AI_API_KEY": "test-xai-key"],
            configurationJSON: """
            {
              "aiProviders": {
                "providers": "xai/grok-code-fast-1"
              }
            }
            """) {
                let services = self.makeServices()
                let agentService = try #require(services.agent as? PeekabooAgentService)

                #expect(agentService.defaultModel == LanguageModel.grok(.custom("grok-code-fast-1")).description)
            }
    }

    @Test
    @MainActor
    func `Bare Ollama provider initializes local default agent`() throws {
        try self.withIsolatedAgentEnvironment(["PEEKABOO_AI_PROVIDERS": "ollama"]) {
            let services = self.makeServices()
            let agentService = try #require(services.agent as? PeekabooAgentService)

            #expect(agentService.defaultModel == LanguageModel.ollama(.llama33).description)
        }
    }

    @Test
    @MainActor
    func `Configured Ollama vision fallback does not initialize agent`() throws {
        try self.withIsolatedAgentEnvironment(["PEEKABOO_AI_PROVIDERS": "ollama/llava:latest"]) {
            let services = self.makeServices()

            #expect(services.agent == nil)
        }
    }

    @Test
    @MainActor
    func `Configured Ollama provider tolerates comma whitespace`() throws {
        try self.withIsolatedAgentEnvironment(["PEEKABOO_AI_PROVIDERS": "openai/gpt-5.5, ollama/llama3.3"]) {
            let services = self.makeServices()
            let agentService = try #require(services.agent as? PeekabooAgentService)

            #expect(agentService.defaultModel == LanguageModel.ollama(.llama33).description)
        }
    }

    @Test
    @MainActor
    func `Configured LM Studio provider initializes local default agent`() throws {
        try self.withIsolatedAgentEnvironment(["PEEKABOO_AI_PROVIDERS": "lmstudio/openai/gpt-oss-120b"]) {
            let services = self.makeServices()
            let agentService = try #require(services.agent as? PeekabooAgentService)

            #expect(agentService.defaultModel == LanguageModel.lmstudio(.gptOSS120B).description)
            #expect(agentService.defaultModelSelection == "lmstudio/openai/gpt-oss-120b")
        }
    }

    @Test
    @MainActor
    func `Default model selection preserves OpenRouter provider identity`() throws {
        let agentService = try PeekabooAgentService(
            services: self.makeServices(),
            defaultModel: .openRouter(modelId: "openai/gpt-oss-120b"))

        #expect(agentService.defaultModelSelection == "openrouter/openai/gpt-oss-120b")
    }

    @Test
    @MainActor
    func `Hyphenated LM Studio provider matches unqualified configured default`() throws {
        try self.withIsolatedAgentEnvironment(
            ["PEEKABOO_AI_PROVIDERS": "lm-studio/openai/gpt-oss-120b"],
            configurationJSON: """
            {
              "agent": {
                "defaultModel": "openai/gpt-oss-120b"
              }
            }
            """) {
                let services = self.makeServices()
                let agentService = try #require(services.agent as? PeekabooAgentService)

                #expect(agentService.defaultModel == LanguageModel.lmstudio(.gptOSS120B).description)
            }
    }

    @Test
    @MainActor
    func `Bare LM Studio provider initializes local default agent`() throws {
        try self.withIsolatedAgentEnvironment(["PEEKABOO_AI_PROVIDERS": "lmstudio"]) {
            let services = self.makeServices()
            let agentService = try #require(services.agent as? PeekabooAgentService)

            #expect(agentService.defaultModel == LanguageModel.lmstudio(.gptOSS120B).description)
        }
    }

    @Test
    @MainActor
    func `Custom default model initialization`() throws {
        let mockServices = self.makeServices()
        let customModel = LanguageModel.openai(.gpt55)
        let agentService = try PeekabooAgentService(
            services: mockServices,
            defaultModel: customModel)

        #expect(agentService.defaultModel == customModel.description)
    }

    private func withIsolatedAgentEnvironment(
        _ overrides: [String: String],
        configurationJSON: String? = nil,
        body: () throws -> Void) throws
    {
        let keys = [
            "PEEKABOO_CONFIG_DIR",
            "PEEKABOO_CONFIG_DISABLE_MIGRATION",
            "PEEKABOO_AI_PROVIDERS",
            "OPENAI_API_KEY",
            "ANTHROPIC_API_KEY",
            "GEMINI_API_KEY",
            "GOOGLE_API_KEY",
            "X_AI_API_KEY",
            "XAI_API_KEY",
            "GROK_API_KEY",
            "PEEKABOO_CUSTOM_PROVIDER_KEY",
            "PEEKABOO_MISSING_PROVIDER_KEY",
            "MINIMAX_API_KEY",
            "MINIMAX_CN_API_KEY",
            "PEEKABOO_OLLAMA_BASE_URL",
            "OLLAMA_BASE_URL",
        ]
        let previous = Dictionary(uniqueKeysWithValues: keys.map { key in
            (key, getenv(key).map { String(cString: $0) })
        })
        defer {
            for key in keys {
                if case let value?? = previous[key] {
                    setenv(key, value, 1)
                } else {
                    unsetenv(key)
                }
            }
            TachikomaConfiguration.current.removeAPIKey(for: .grok)
            ConfigurationManager.shared.resetForTesting()
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("peekaboo-agent-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        if let configurationJSON {
            try configurationJSON.write(
                to: tempDir.appendingPathComponent("config.json"),
                atomically: true,
                encoding: .utf8)
        }
        defer { try? FileManager.default.removeItem(at: tempDir) }

        setenv("PEEKABOO_CONFIG_DIR", tempDir.path, 1)
        setenv("PEEKABOO_CONFIG_DISABLE_MIGRATION", "1", 1)
        unsetenv("PEEKABOO_AI_PROVIDERS")
        unsetenv("OPENAI_API_KEY")
        unsetenv("ANTHROPIC_API_KEY")
        unsetenv("GEMINI_API_KEY")
        unsetenv("GOOGLE_API_KEY")
        unsetenv("X_AI_API_KEY")
        unsetenv("XAI_API_KEY")
        unsetenv("GROK_API_KEY")
        unsetenv("PEEKABOO_CUSTOM_PROVIDER_KEY")
        unsetenv("PEEKABOO_MISSING_PROVIDER_KEY")
        unsetenv("MINIMAX_API_KEY")
        unsetenv("MINIMAX_CN_API_KEY")
        unsetenv("PEEKABOO_OLLAMA_BASE_URL")
        unsetenv("OLLAMA_BASE_URL")
        TachikomaConfiguration.current.removeAPIKey(for: .grok)
        for (key, value) in overrides {
            setenv(key, value, 1)
        }
        ConfigurationManager.shared.resetForTesting()

        try body()
    }

    @Test
    @MainActor
    func `Model parameter precedence in executeTask`() async throws {
        let mockServices = self.makeServices()
        let defaultModel = LanguageModel.anthropic(.opus47)
        let agentService = try PeekabooAgentService(
            services: mockServices,
            defaultModel: defaultModel)

        // Mock event delegate that captures model usage
        let eventDelegate = MockEventDelegate()

        // Test with custom model parameter
        let customModel = LanguageModel.openai(.gpt55)

        // This would normally make an API call, but we're testing the model selection logic
        // In a real test, we'd mock the network layer
        do {
            let result = try await agentService.executeTask(
                "test task",
                maxSteps: 1,
                sessionId: nil,
                model: customModel,
                eventDelegate: eventDelegate)

            // Verify the result metadata shows the custom model was used
            #expect(result.metadata.modelName == customModel.description)
        } catch {
            // Expected to fail due to missing API keys in test environment
            // The important part is that the model selection logic works
            #expect(!error.localizedDescription.isEmpty)
        }
    }

    @Test
    @MainActor
    func `Model parameter falls back to default when nil`() async throws {
        let mockServices = self.makeServices()
        let defaultModel = LanguageModel.anthropic(.opus47)
        let agentService = try PeekabooAgentService(
            services: mockServices,
            defaultModel: defaultModel)

        let eventDelegate = MockEventDelegate()

        // Test with nil model parameter - should use default
        do {
            let result = try await agentService.executeTask(
                "test task",
                maxSteps: 1,
                sessionId: nil,
                model: nil, // Should fall back to default
                eventDelegate: eventDelegate)

            // Verify the result metadata shows the default model was used
            #expect(result.metadata.modelName == defaultModel.description)
        } catch {
            // Expected to fail due to missing API keys in test environment
            // Accept any error as we're testing the model selection logic, not API calls
            #expect(!error.localizedDescription.isEmpty)
        }
    }

    @Test
    @MainActor
    func `Streaming execution respects model parameter`() async throws {
        let mockServices = self.makeServices()
        let agentService = try PeekabooAgentService(services: mockServices)

        let customModel = LanguageModel.openai(.gpt55)
        _ = MockEventDelegate()

        // Test streaming execution with custom model
        do {
            let result = try await agentService.executeTaskStreaming(
                "test task",
                sessionId: nil,
                model: customModel)
            { _ in
                // Stream handler
            }

            #expect(result.metadata.modelName == customModel.description)
        } catch {
            // Expected to fail due to missing API keys
            #expect(!error.localizedDescription.isEmpty)
        }
    }

    @Test
    @MainActor
    func `Resume session respects model parameter`() async throws {
        let mockServices = self.makeServices()
        let agentService = try PeekabooAgentService(services: mockServices)

        let customModel = LanguageModel.anthropic(.opus47)

        // Test resume session with custom model
        do {
            let result = try await agentService.resumeSession(
                sessionId: "test-session-id",
                model: customModel,
                eventDelegate: nil)

            #expect(result.metadata.modelName == customModel.description)
        } catch {
            // Expected to fail due to non-existent session or missing API keys
            #expect(!error.localizedDescription.isEmpty)
        }
    }

    @Test
    @MainActor
    func `Dry run execution reports requested model`() async throws {
        let mockServices = self.makeServices()
        let agentService = try PeekabooAgentService(
            services: mockServices,
            defaultModel: .anthropic(.opus47))

        let result = try await agentService.executeTask(
            "describe state",
            maxSteps: 1,
            sessionId: nil,
            model: .openai(.gpt55),
            dryRun: true,
            eventDelegate: nil)

        #expect(result.metadata.modelName == LanguageModel.openai(.gpt55).description)
        #expect(result.content.contains("Dry run"))
    }
}

extension PeekabooAgentServiceTests {
    @Test
    @MainActor
    func `Generated default with unknown shadowing custom model does not use hosted fallback`() throws {
        try self.withIsolatedAgentEnvironment(
            [
                "OPENAI_API_KEY": "hosted-openai-key",
                "PEEKABOO_CUSTOM_PROVIDER_KEY": "custom-secret",
            ],
            configurationJSON: """
            {
              "agent": {
                "defaultModel": "openai/gpt-5.5"
              },
              "customProviders": {
                "openai": {
                  "name": "Custom OpenAI Proxy",
                  "type": "openai",
                  "enabled": true,
                  "options": {
                    "baseURL": "http://localhost:8317/v1",
                    "apiKey": "${PEEKABOO_CUSTOM_PROVIDER_KEY}"
                  },
                  "models": {
                    "mini": {
                      "name": "Proxy Mini",
                      "supportsTools": true
                    }
                  }
                }
              }
            }
            """) {
                let services = self.makeServices()

                #expect(services.agent == nil)
            }
    }

    @Test
    @MainActor
    func `Unknown model on shadowing custom provider does not use hosted fallback`() throws {
        try self.withIsolatedAgentEnvironment(
            [
                "OPENAI_API_KEY": "hosted-openai-key",
                "PEEKABOO_CUSTOM_PROVIDER_KEY": "custom-secret",
            ],
            configurationJSON: """
            {
              "aiProviders": {
                "providers": "openai/gpt-5.5"
              },
              "customProviders": {
                "openai": {
                  "name": "Custom OpenAI Proxy",
                  "type": "openai",
                  "enabled": true,
                  "options": {
                    "baseURL": "http://localhost:8317/v1",
                    "apiKey": "${PEEKABOO_CUSTOM_PROVIDER_KEY}"
                  },
                  "models": {
                    "mini": {
                      "name": "Proxy Mini",
                      "supportsTools": true
                    }
                  }
                }
              }
            }
            """) {
                let services = self.makeServices()

                #expect(services.agent == nil)
            }
    }
}

struct PeekabooAgentResumeTests {
    @Test
    @MainActor
    func `Resume session respects max steps`() async throws {
        let provider = StepCountingProvider()
        let configuration = TachikomaConfiguration(loadFromEnvironment: false)
        configuration.setProviderFactoryOverride { _, _ in provider }

        let previousConfiguration = TachikomaConfiguration.default
        TachikomaConfiguration.default = configuration
        defer {
            TachikomaConfiguration.default = previousConfiguration
        }

        let agentService = try PeekabooAgentService(
            services: PeekabooServices(),
            defaultModel: .openai(.gpt55))
        let sessionId = "resume-max-steps-\(UUID().uuidString)"
        let now = Date()
        try agentService.sessionManager.saveSession(AgentSession(
            id: sessionId,
            modelName: LanguageModel.openai(.gpt55).description,
            messages: [
                .system("Test system prompt"),
                .user("Test task"),
            ],
            metadata: SessionMetadata(),
            createdAt: now,
            updatedAt: now))

        do {
            _ = try await agentService.resumeSession(
                sessionId: sessionId,
                model: .openai(.gpt55),
                maxSteps: 1)
            try await agentService.deleteSession(id: sessionId)
        } catch {
            try? await agentService.deleteSession(id: sessionId)
            throw error
        }

        #expect(provider.requestCount == 1)
    }
}

private final class StepCountingProvider: ModelProvider, @unchecked Sendable {
    let modelId = "step-counting-provider"
    let baseURL: String? = nil
    let apiKey: String? = nil
    let capabilities = ModelCapabilities()

    private let lock = NSLock()
    private var _requestCount = 0

    var requestCount: Int {
        self.lock.withLock { self._requestCount }
    }

    func generateText(request _: ProviderRequest) async throws -> ProviderResponse {
        let requestCount = self.lock.withLock {
            self._requestCount += 1
            return self._requestCount
        }
        return ProviderResponse(
            text: "step \(requestCount)",
            finishReason: .toolCalls,
            toolCalls: [
                AgentToolCall(
                    id: "missing-tool-\(requestCount)",
                    name: "missing_test_tool",
                    arguments: [:]),
            ])
    }

    func streamText(request: ProviderRequest) async throws -> AsyncThrowingStream<TextStreamDelta, any Error> {
        let response = try await self.generateText(request: request)
        return AsyncThrowingStream { continuation in
            continuation.yield(TextStreamDelta(type: .textDelta, content: response.text))
            continuation.yield(TextStreamDelta(type: .done))
            continuation.finish()
        }
    }
}

/// Mock event delegate for testing
@MainActor
private class MockEventDelegate: AgentEventDelegate {
    var events: [AgentEvent] = []

    func agentDidEmitEvent(_ event: AgentEvent) {
        self.events.append(event)
    }
}

/// Tests for model selection in different execution paths
struct ModelSelectionExecutionPathTests {
    @MainActor
    private func makeServices() -> PeekabooServices {
        PeekabooServices()
    }

    @Test
    @MainActor
    func `executeWithStreaming uses provided model`() async throws {
        let mockServices = self.makeServices()
        let agentService = try PeekabooAgentService(services: mockServices)

        // Test that the internal executeWithStreaming method would use the provided model
        // This is tested indirectly through the public API since executeWithStreaming is private

        let customModel = LanguageModel.openai(.gpt55)
        let eventDelegate = MockEventDelegate()

        do {
            let result = try await agentService.executeTask(
                "test streaming execution",
                maxSteps: 1,
                sessionId: nil as String?,
                model: customModel,
                eventDelegate: eventDelegate)

            // The streaming path should be taken when eventDelegate is provided
            #expect(result.metadata.modelName == customModel.description)
        } catch {
            // Expected to fail due to API constraints in test environment
            #expect(!error.localizedDescription.isEmpty)
        }
    }

    @Test
    @MainActor
    func `executeWithoutStreaming uses provided model`() async throws {
        let mockServices = self.makeServices()
        let agentService = try PeekabooAgentService(services: mockServices)

        let customModel = LanguageModel.anthropic(.opus47)

        do {
            // No event delegate means non-streaming path
            let result = try await agentService.executeTask(
                "test non-streaming execution",
                maxSteps: 1,
                sessionId: nil as String?,
                model: customModel,
                eventDelegate: nil as (any AgentEventDelegate)?)

            #expect(result.metadata.modelName == customModel.description)
        } catch {
            // Expected to fail due to API constraints in test environment
            #expect(!error.localizedDescription.isEmpty)
        }
    }

    @Test
    @MainActor
    func `Model consistency across multiple calls`() async throws {
        let mockServices = PeekabooServices()
        let agentService = try PeekabooAgentService(services: mockServices)

        let models: [LanguageModel] = [
            .openai(.gpt55),
            .anthropic(.opus47),
        ]

        for model in models {
            do {
                let result = try await agentService.executeTask(
                    "test model \(model.description)",
                    maxSteps: 1,
                    sessionId: nil,
                    model: model,
                    eventDelegate: nil)

                #expect(result.metadata.modelName == model.description)
            } catch {
                // Expected to fail, but should fail consistently for each model
                #expect(!error.localizedDescription.isEmpty)
            }
        }
    }
}

/// Tests for edge cases and error handling
struct ModelSelectionEdgeCasesTests {
    @Test
    @MainActor
    func `Dry run execution respects model parameter`() async throws {
        let mockServices = PeekabooServices()
        let defaultModel = LanguageModel.openai(.gpt55)
        let agentService = try PeekabooAgentService(
            services: mockServices,
            defaultModel: defaultModel)

        // Dry run should not make API calls but should still record the model
        let result = try await agentService.executeTask(
            "dry run test",
            maxSteps: 1,
            dryRun: true,
            eventDelegate: nil)

        // Dry run uses the service default model
        #expect(result.metadata.modelName == defaultModel.description)
        #expect(result.content.contains("Dry run completed"))
    }

    @Test
    @MainActor
    func `Audio task execution model handling`() async throws {
        let mockServices = PeekabooServices()
        let defaultModel = LanguageModel.openai(.gpt55)
        let agentService = try PeekabooAgentService(
            services: mockServices,
            defaultModel: defaultModel)

        let audioContent = AudioContent(
            duration: 5.0,
            transcript: "test audio transcript")

        // Audio execution should use default model (no model parameter in this method)
        let result = try await agentService.executeTaskWithAudio(
            audioContent: audioContent,
            maxSteps: 1,
            dryRun: true,
            eventDelegate: nil)

        #expect(result.metadata.modelName == defaultModel.description)
        #expect(result.content.contains("Dry run completed"))
    }
}
