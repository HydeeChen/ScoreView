//
//  ChatHelper.swift
//  TaiwanTextClient
//
//  Created by KenChang on 2022/9/6.
//  Copyright © 2022 TaiwanTaxi. All rights reserved.
//
import Foundation
import CleanJSON
import TaiwanTaxiSDKIOS
protocol ChatHelperProtocol: AnyObject {
func connect()
func disconnect()
func messageIsRead(messageIds: [Int]) //
func updatedChatMessage()
}
extension ChatHelperProtocol {
func connect() { }
func disconnect() { }
func messageIsRead(messageIds: [Int]){ } //
func updatedChatMessage() { }
}
extension NSNotification.Name {
static let newChatMessage = NSNotification.Name(rawValue: "newChatMessage")
}
class ChatHelper {
    internal var delegates: [String: ChatHelperProtocol] = [:]
    weak var chatMgr: ChatManager?

    // 方便取用
    public var isEnterChatVC: [String:Bool] = [:] //

    static let shared: ChatHelper = {
        let instance = ChatHelper()
        return instance
    }()

    // FIXME: 搬進 ChatManager 內
    func getSocketIsDisconnect() -> Bool {
        // 先檢查 socket 是否有初始化過
        guard let socket = ChatManager.shared.socket else { return true }
        return socket.status == .disconnected
    }

    // FIXME: 搬進 ChatManager 內
    func getSocketIsConnected() -> Bool {
        //MARK: 觸發網路斷線時，socket 不一定會馬上進入 connected，此時若送出訊息，顯示會異常，故需先判斷網路。
        if TTNetworkManager.sharedInstance.getNetworkReachabilityStatus() == .notReachable {
            return false
        }
        
        // 先檢查 socket 是否有初始化過
        guard let socket = ChatManager.shared.socket else { return false }
        return socket.status == .connected
    }

    /// 連線 Socket
    /// - Parameters:
    ///   - chatToken: 聊天 token
    ///   - completeHandler: 連線後，交由外層實作後續行為，並告訴外層連線是否成功
    public func connectChatSocket(_ chatToken: String,
                                   completeHandler: @escaping (Bool)->() ) {
        
        // 取得 chatToken 後，初始化 Socket，並且直接連線
        ChatManager.shared.initSocketWithChatToken(chatToken)
        ChatManager.shared.establishConnection { [weak self] status in
            print("聊天室狀態 ：\(status.description)")
            switch status {
                case .notConnected:
                    completeHandler(false)
                case .disconnected:
                    self?.chatMgr?.stopHeartbeat()
                    completeHandler(false)
                case .connecting:
                    completeHandler(false)
                case .connected:
                    //建立連線
                    self?.chatMgr?.startHeartbeat()
                    self?.reJoinToChat()
                    completeHandler(true)
            }
        }
    }

    /// 加入聊天室
    func joinToChat(_ jobIds: [String]?) {
        guard let jobIds = jobIds else { return }

        // 逐筆
        for jobId in jobIds {
            if jobId.isEmpty {
                continue
            }
            
            let chatInfoModel: ChatInfoModel = TTModelHelper.getChatInfoModel()

            // 該任務已經有聊天室紀錄，不再次修改
            if (chatInfoModel.has(inChatList: jobId)){
                continue
            }//

            // joinToChat 前，當作無法使用聊天訊息，先加入列表
            chatInfoModel.updateCanChatList(jobId, isEnable: false)

            // 除文件上寫的 conneect 與 reconneect 會觸發，App 移到背景過一陣子約 15 秒，再次打開 App，connect 也會被不知道從哪觸發，故要清除資料，否則會重複加入訊息。
            // FIXME: 這段感覺可以在 for 迴圈外執行
            chatInfoModel.removeChatMessage(jobIds)

            // 要測試 Disconnect 流程
            // 加入聊天室
            chatMgr?.joinToChat(jobId, completeClosure: { jobId, isSuccess in
                print(jobId, isSuccess)
                self.isEnterChatVC[jobId] = false //
                // 加入的事件完成後，不論成功或失敗，都要記錄下來，以這個紀錄當作是否開啟文字通訊功能的依據
                chatInfoModel.updateCanChatList(jobId, isEnable: isSuccess)
            })
        }
    }

    /// 重新連線後，重新加入聊天室
    func reJoinToChat() {
        let model: ChatInfoModel = TTModelHelper.getChatInfoModel()
        let ids = model.getChatList()

        guard let jobIds = ids else { return }

        // 逐筆
        for jobId in jobIds {
            // 原本就能聊天的任務，再次加入聊天室
            let chatInfoModel: ChatInfoModel = TTModelHelper.getChatInfoModel()
            if chatInfoModel.canChat(jobId) {
                chatMgr?.reJoinToChat(jobId, completeClosure: { jobId, isSuccess in
                    print("再次加入聊天室", jobId, isSuccess)
                })
            }
        }
    }

    /// 發送訊息到聊天室
    public func sendMessage(_ jobId: String, chatMessage: ChatMessage) {
        chatMgr?.sendMessage(jobId, chatMessage: chatMessage)
    }

    /// 解析並更新已取得的聊天訊息
    // FIXME: 目前看起來沒有使用
    public func updateChatContent(_ jobId: String? = nil, data: [Any]) {
        if let str = data.first as? String {
            print("資料非 Dictionary:\(str)")
            return
        }
        
        let dic: Dictionary = data.first as! Dictionary<String, Any>

        do {
            let msg = try CleanJSONDecoder().decode(ChatMessages.self, from: dic)
            let tempJobId = jobId ?? msg.jobId
            updateChatMessage(jobId: tempJobId, messages: msg.messages)
        } catch {
            print(error)
        }
    }

    /// 解析並更新已取得的聊天訊息(會過濾已顯示訊息流程)
    public func appendChatContent(_ jobId: String? = nil, data: [Any], chatMessage: ChatMessage? = nil) {
        if let str = data.first as? String {
            print("資料非 Dictionary:\(str)")
            return
        }

        let dic: Dictionary = data.first as! Dictionary<String, Any>

        do {
            let msg = try CleanJSONDecoder().decode(ChatMessages.self, from: dic)
            let chatInfoModel: ChatInfoModel = TTModelHelper.getChatInfoModel()

            guard let chatMessage = chatMessage else {
                // chatMessage 直接由 server 下放的訊息或是乘客傳過來的訊息，因為不是 Client 發出，故一開始就不會有 ChatMessage 物件
                for message in msg.messages {
                    let obj: ChatMessage = ChatMessage(sendText: "")
                    obj.chatMessageData = message
                    chatInfoModel.updateChatMessage(jobId ?? msg.jobId, messages: [obj])
                }

                self.delegates.forEach { (key: String, value: ChatHelperProtocol) in
                    value.updatedChatMessage()
                }
                self.checkHasNewMessage((jobId ?? msg.jobId) ?? "") //

                return
            }

            chatMessage.chatMessageData = msg.messages.first
            chatInfoModel.updateChatMessage(jobId ?? msg.jobId, messages: [chatMessage])
            self.delegates.forEach { (key: String, value: ChatHelperProtocol) in
                value.updatedChatMessage()
            }
            self.checkHasNewMessage((jobId ?? msg.jobId) ?? "")
        } catch {
            print(error)
        }
    }

    /// 更新傳送失敗的聊天訊息
    public func updateFailChatContent(_ jobId: String, chatMessage: ChatMessage) {
        let chatInfoModel: ChatInfoModel = TTModelHelper.getChatInfoModel()
        chatInfoModel.updateChatMessage(jobId, messages: [chatMessage])
        self.delegates.forEach { (key: String, value: ChatHelperProtocol) in
            value.updatedChatMessage()
        }
    }

    /// 分類已取得的聊天訊息
    internal func updateChatMessage(jobId: String?, messages: [ChatMessageData]) {
        guard let jobId = jobId else {
            print("無 jobId，故無法歸類為哪個任務的聊天室")
            return
        }

        let chatInfoModel: ChatInfoModel = TTModelHelper.getChatInfoModel()
        chatInfoModel.updateChatMessage(jobId, messages: messages) { updateJobId in
            //TODO: 完成的訊息
            self.delegates.forEach { (key: String, value: ChatHelperProtocol) in
                value.updatedChatMessage()
            }
        }
    }

    /// 斷線
    public func disconnect() {
        self.delegates.forEach { (key: String, value: ChatHelperProtocol) in
            print("！！！！！！！聊天室斷線！！！！！！！！")
            value.disconnect()
        }
        
        //兩秒後重連
        SwiftClockTools.delayWithSeconds(2) { [self] in
            print("！！！！！！！聊天室重新連線！！！！！！！！")
            reconnect()
        }
    }

    /// 連線
    public func connect() {
        self.delegates.forEach { (key: String, value: ChatHelperProtocol) in
            value.connect()
        }
    }

    /// 回報已讀過的訊息
    public func reportJobMessages(_ jobId: String) {
        let chatInfoModel: ChatInfoModel = TTModelHelper.getChatInfoModel()

        guard let chatMessageDatas = chatInfoModel.getChatMessages(withJobId: jobId) else { return }
        let chatMessages:[ChatMessage] = chatMessageDatas as! [ChatMessage]

        let contents = chatMessages.compactMap( { $0.chatMessageData } )
        let messages:[ChatMessageData] = contents.filter( { $0.isNotDriver() && $0.isNotRead() } )
        var messageIds:[Int] = messages.map( {$0.id} )

        let model:ChatInfoModel = TTModelHelper.getChatInfoModel()
        let sentReadMessageIds = model.getSentReadMessageIdsList() as! [Int]
        messageIds = messageIds.filter { !sentReadMessageIds.contains($0) }

        if messageIds.count >= 1 {
            chatMgr?.readMessage(jobId, messageIds: messageIds)
        }
    }

    public func reconnect() {
        let userDataM: UserDataModel = TTModelHelper.getUserDataModel()
        guard let chatToken = userDataM.userInfo?.JWTToken?.chatToken else {
            return
        }

        connectChatSocket(chatToken) { [self] isSuccess in
            //自動重連後自動加入的聊天室
            if isSuccess {
                reJoinToChat()
            }
            print("重新加入聊天室: " ,isSuccess )
        }
    }

    public func readMessage(_ messageIds: [Int]) {
        let model:ChatInfoModel = TTModelHelper.getChatInfoModel()
        model.updateSentReadMessageIdsList(messageIds)
    }

    /// 解析已讀的聊天ID
    public func messageIsRead(_ data: [Any]) {
        if let str = data.first as? String {
            print("資料非 Dictionary:\(str)")
            return
        }

        let dic: Dictionary = data.first as! Dictionary<String, Any>

        do {
            let data = try CleanJSONDecoder().decode(MessageIsRead.self, from: dic)
            self.delegates.forEach { (key: String, value: ChatHelperProtocol) in
                value.messageIsRead(messageIds: data.messageIds)
            }
        } catch {
            print(error)
        }
    }

    /// 離開聊天室
    public func leaveChat(_ jobId: String) {
        chatMgr?.leaveChat(jobId)
        isEnterChatVC.removeValue(forKey: jobId)
    }

    /// 解析並更新已取得的聊天訊息(會過濾已顯示訊息流程)
    public func setHasNewMessageList(data: [Any]) {
        if let str = data.first as? String {
            print("資料非 Dictionary:\(str)")
            return
        }

        let dic: Dictionary = data.first as! Dictionary<String, Any>

        do {
            let msg = try CleanJSONDecoder().decode(ChatMessages.self, from: dic)
            let chatInfoModel: ChatInfoModel = TTModelHelper.getChatInfoModel()
            chatInfoModel.updateHasNewMessageList(msg.jobId, hasNewMessage: true)
        } catch {
            print(error)
        }
    }

    /// 檢查是否有未讀訊息
    public func checkHasNewMessage(_ jobId: String) {
        print("檢查是否有未讀訊息")
        let chatInfoModel: ChatInfoModel = TTModelHelper.getChatInfoModel()
        
        // 先撈出該 jobId 所有 ChatMessage
        guard let chatMessageDatas = chatInfoModel.getChatMessages(withJobId: jobId) else { return }
        let chatMessages:[ChatMessage] = chatMessageDatas as! [ChatMessage]
        
        // 過濾出由乘客傳送並尚未已讀過的訊息，將這些訊息的 id 取出
        let contents = chatMessages.compactMap( { $0.chatMessageData } )
        let messages:[ChatMessageData] = contents.filter( { $0.role == 0 && $0.isRead == 0} )
        var messageIds:[Int] = messages.map( {$0.id} )
        
        // 將上面的 id 再過濾出沒有傳送過已讀的訊息 id
        let model:ChatInfoModel = TTModelHelper.getChatInfoModel()
        let sentReadMessageIds = model.getSentReadMessageIdsList() as! [Int]
        messageIds = messageIds.filter { !sentReadMessageIds.contains($0) }
        
        // messageIds 若裡面有值，就代表還有訊息沒有已讀
        if messageIds.count > 0 {
            RemoteNotificationModel.setHasMessageDic( jobId, true )
        }
        else{
            RemoteNotificationModel.setHasMessageDic( jobId, false )
        }
        
        // 發出更新 badget 的 notification
        NotificationCenter.default.post( name: NSNotification.Name( D_Notification_UpdateChatBadget ) ,
                                         object: nil )
        /// 發送本地推播
        public func sendLocalNotification( data: [Any] ) {
            if let str = data.first as? String {
#if D_Dev_Ver
                print("資料非 Dictionary:\(str)")
#endif
                return
            }
            
            let dic: Dictionary = data.first as! Dictionary<String, Any>
            
            do {
                let msg = try CleanJSONDecoder().decode( ChatMessages.self , from: dic )
                if let jobID = msg.jobId ,
                   let queryJob = JobModel.findQueryJob( jobID ) ,
                   isEnterChatVC[jobID] == false {
                    
                    // 建立 Title : 乘客 ${乘客姓名}
                    let chatTitle = "乘客 \(queryJob.jobExInfo?.CustInfo?.CustName ?? "")"
                    // 建立 chat message
                    let model: UserDataModel = TTModelHelper.getUserDataModel()
                    let chatMsgData = msg.messages.first
                    let chatMsg = chatMsgData?.message ?? ""
                    let memSN = String( model.userInfo?.MemSN ?? 0)
                    
                    let content = ChatNotificationObj( alertTitle: chatTitle ,
                                                       alertMsg: chatMsg,
                                                       jobID: jobID,
                                                       memSN: memSN,
                                                       action: .showChat,
                                                       category: .chatMsg )
                    
                    AppPushNotification.createLocalNotification( content ) { isSuccess , error in
#if D_Dev_Ver
                        if isSuccess {
                            print(" Create Local Notification success. ")
                        }
                        else {
                            print(" Create Local Notification fail!!! (\(error)) ")
                        }
#endif
                    }
                    NotificationCenter.default.post( name: NSNotification.Name( D_Notification_UpdateChatBadget ) ,
                                                     object: nil )
                }
            } catch {
                print(error)
            }
        }
        
        /// 發送有新訊息的廣播
        public func sendNotification(data: [Any]) {
            
            if let str = data.first as? String {
#if D_Dev_Ver
                print("資料非 Dictionary:\(str)")
#endif
                return
            }
            
            let dic: Dictionary = data.first as! Dictionary<String, Any>
            
            do {
                let msg = try CleanJSONDecoder().decode(ChatMessages.self, from: dic)
                
                if let jobId = msg.jobId {
                    let dic:[String: String] = ["jobId": jobId]
                    NotificationCenter.default.post(name: .newChatMessage, object: nil, userInfo: dic)
                }
            } catch {
                print(error)
            }
        }
    }
}

extension ChatHelper {
    
    static public func handleChatAfterDispatchQuery( _ tempVehicleObjArray: [VehicleObj]? ){
        guard let vObjs = tempVehicleObjArray else { return }
        let supportChatrooms: [VehicleObj] = vObjs.getSupportChatVehicleObj()
        let notSupportChatrooms: [VehicleObj] = vObjs.getNotSupportChatVehicleObj()
        //由於連線 socket 有後端成本，故使用者有等車中的任務，才連線 socket
        if supportChatrooms.count > 0 {
            
            //沒有初始化
            guard let socket = ChatManager.shared.socket else {
                guard let chatToken = TTModelHelper.getChatInfoModel().chatToken else {
                    return
                }
                
                ChatHelper.shared.connectChatSocket( chatToken ) { isSuccess in
                    //成功建立連線，立即加入聊天室
                    if isSuccess {
                        ChatHelper.joinChats( supportChatrooms )
                        ChatHelper.leaveChats( notSupportChatrooms )
                    }
                }
                return
            }
            if ( socket.status == .connected ){
                ChatHelper.joinChats( supportChatrooms )
                ChatHelper.leaveChats( notSupportChatrooms )
            }
        }
        else {
            if notSupportChatrooms.count > 0 {
                //沒有初始化，就不需花費連線成本
                guard let socket = ChatManager.shared.socket else {
                    return
                }
                if (socket.status == .connected){
                    leaveChats( notSupportChatrooms )
                }
            }
        }
    }
    
    static private func joinChats( _ supportChatrooms: [VehicleObj]? ){
        guard let supportChatrooms = supportChatrooms else { return }
        let jobIds = supportChatrooms.map( {$0.jobId!} )
        ChatHelper.shared.joinToChat( jobIds )
    }
    
    static private func leaveChats( _ notSupportChatrooms: [VehicleObj]? ){
        guard let notSupportChatrooms = notSupportChatrooms else { return }
        let jobIds = notSupportChatrooms.map( {$0.jobId!} )
        for jobId in jobIds {
            if jobId.isEmpty {
                continue
            }
            let chatInfoModel: ChatInfoModel = TTModelHelper.getChatInfoModel()
            if chatInfoModel.hasLeave(jobId){
#if D_Dev_Ver
                print(" \(jobId) 已離開聊天室，不重複送")
#endif
            } else {
                chatInfoModel.updateLeaveChatList( jobId )
                ChatHelper.shared.leaveChat( jobId )
            }
        }
    }
}


