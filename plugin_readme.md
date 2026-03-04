| 渠道 | 插件 ID | 安装命令 | 状态 |                                                                                            
 |------|---------|----------|--- ---|                                                                                           
 | WhatsApp | @openclaw/whatsapp | openclaw plugins install @openclaw/whatsapp | 内置 |                                          
 | Telegram | @openclaw/telegram | openclaw plugins install @openclaw/telegram | 内置 |                                          
 | Discord | @openclaw/discord | openclaw plugins install @openclaw/discord | 内置 |                                             
 | iMessage | @openclaw/imessage | openclaw plugins install @openclaw/imessage | 内置 |                                          
 | Slack | @openclaw/slack | openclaw plugins install @openclaw/slack | 内置 |                                                   
 | Signal | @openclaw/signal | openclaw plugins install @openclaw/signal | 内置 |                                                
 | Mattermost | @openclaw/mattermost | openclaw plugins install @openclaw/mattermost | 内置 |                                    
 | Google Chat | @openclaw/googlechat | openclaw plugins install @openclaw/googlechat | 内置 |                                   
 | Microsoft Teams | @openclaw/msteams | openclaw plugins install @openclaw/msteams | 内置 |                                     
 | IRC | @openclaw/irc | openclaw plugins install @openclaw/irc | 内置 |                                                         
 | Matrix | @openclaw/matrix | openclaw plugins install @openclaw/matrix | 内置 |                                                
 | LINE | @openclaw/line | openclaw plugins install @openclaw/line | 内置 |                                                      
 | Nextcloud Talk | @openclaw/nextcloud-talk | openclaw plugins install @openclaw/nextcloud-talk | 内置 |                        
 | Synology Chat | @openclaw/synology-chat | openclaw plugins install @openclaw/synology-chat | 内置 |                           
 | Zalo | @openclaw/zalo | openclaw plugins install @openclaw/zalo | 内置 |                                                      
 | 钉钉 (DingTalk) | dingtalk | openclaw plugins install dingtalk | ✅ 已加载 |                                                  
 | 飞书 (Feishu) | @openclaw/feishu | openclaw plugins install @openclaw/feishu | 内置 |                                         
                                                                                                                                 
 ────────────────────────────────────────────────────────────────────────────────                                                
                                                                                                                                 
 安装后启用插件：                                                                                                                
                                                                                                                                 
 ```bash                                                                                                                         
   openclaw plugins enable <插件ID>                                                                                              
 ```                                                                                                                             
                                                                                                                                 
 查看已安装的插件：                                                                                                              
                                                                                                                                 
 ```bash                                                                                                                         
   openclaw plugins list                                                                                                         
 ```                                                                                                                             
                                                                                                                                 
 配置渠道：                                                                                                                      
                                                                                                                                 
 ```bash                                                                                                                         
   openclaw channels add --channel <渠道名> --token <凭证> 