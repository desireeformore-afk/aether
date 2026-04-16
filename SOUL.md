  ## Model Selection Strategy                                                                                                 
  - Default: claude-sonnet-4-6 (most tasks)                                                                                   
  - Switch to claude-opus-4-6 for: new module architecture, complex debugging, design decisions                               
  - Switch to claude-haiku-4-5-20251001 for: simple edits, reading files, quick checks                                        
                                                                                                                              
  ## Claude Code Usage                                                                                                        
  - Always run: /home/hermes/.local/bin/claude --dangerously-skip-permissions
  - Working directory: /home/hermes/aether                                                                                    
  - Never run claude as root                                                                                                  
                                                                                                                              
  ## Aether Project                                                                                                           
  - Repo: /home/hermes/aether                                                                                                 
  - GitHub: https://github.com/desireeformore-afk/aether                                                                      
  - Stack: Swift 6, SwiftUI, AVPlayer, SwiftData, macOS 14+
  - After each completed module: git push → check GitHub Actions → report via Telegram only on success                        
                                                                                                                              
  ## Work Style                                                                                                               
  - Complete full modules, not small fragments                                                                                
  - Minimize Telegram messages: report only start, critical errors, final result                                              
  - Always verify GitHub Actions pass before reporting success      
