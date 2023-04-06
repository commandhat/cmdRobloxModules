--[[**
    Run gildedRadio.setup in your script to make the module ready to interact with your server. If the return value is anythiing that isn't 0, then either your authKey or serverID is incorrect.
    This module has extensive documentation! Install the Documentation Reader plugin to read the docs from inside Studio. https://devforum.roblox.com/t/documentation-reader-a-plugin-for-scripters/128825
    Track this plugin on Github: 
**--]]
local gildedRadio = {}
local authHolder = nil
local servIDHolder = nil
local shouldLogCalls = nil
local retryBackoff = 0

--[[**
    Sets up the module to interact with a Guilded server. WARNING: Makes an HTTP request to verify Guilded connectivity.
    
    @param authKey[string,required] The authentication key used for your Guilded Bot. Make sure this is kept somewhere safe and private, like in ServerStorage!
    @param  serverID[string,required] The ID used for your server. Inside Guilded, enable Developer Mode, then right click your Server Icon on the left and click 'Copy Server ID.'
    @param logCalls[boolean] whether or not gildedRadio should log HTTPService calls. If this is true, then gildedRadio will create an Event as a child underneath it called "HTTPCall". Each request gildedRadio makes will be echoed into the event, allowing for wrappers to log each call.
    
    @returns This function returns true if the module initialized successfully. If it returns false, something went wrong, check the console to learn what went wrong.
**--]]
function gildedRadio.setup(authKey: string,serverID: string,logCalls: boolean)
	authHolder = authKey
	servIDHolder = serverID
	shouldLogCalls = logCalls
	if gildedRadio.shouldLogCalls then
		local logCallObject = Instance.new("BindableEvent")
		logCallObject.Name = "HTTPCall"
		logCallObject.Parent = script
	end
	local resultData = gildedRadio.internalMakeRequest(5,"servers/" ..servIDHolder)
	if resultData then return true else return false end
end

--[[**
    This function is the module's HTTPService API wrapper. Please do not touch it. If you want to log gildedRadio requests, please read the documentation for gildedRadio.setup() instead.
    
    The default is seven retries because the last try requires a full minute of cooldown time. If, after a full minute, the last attempt still fails, it is assumed Guilded's API is down or unresponsive.
    
    @param mode[number,required]
    
    0: POST
    1: GET
    2: PUT
    3: PATCH
    4: DELETE
    5: HEAD
    
    Any other value will make the function throw an error.
    @param ApiURL[string,required] The portion of the API you want to make a request to. 
    @param requestData[table] A table containing the data you want sent. DO NOT JSONENCODE THIS TABLE, IT IS DONE INSIDE THIS FUNCTION.

	@returns A decoded JSON table containing any response the Guilded API sent back. Can cause warns or errors if the response is bad.
**--]]
function gildedRadio.internalMakeRequest(mode: number,ApiURL: string,requestData: any)
	local HTTPS = game:GetService("HttpService")
	local baseUrl = "https://www.guilded.gg/api/v1/"
	local response
	local Data
	local builtRequest = {}
	builtRequest.Url = baseUrl.. "" ..ApiURL
	local tab = {[0]="POST", [1]="GET",[2]="PUT",[3]="PATCH",[4]="DELETE",[5]="HEAD"}
	builtRequest.Method = tab[mode]
	builtRequest.Headers = {}
	local fixedString = "Bearer " ..authHolder
	builtRequest.Headers["Authorization"] = fixedString
	builtRequest.Headers["Accept"] = "application/json"
	builtRequest.Headers["Content-type"] = "application/json"
	if requestData ~= nil then builtRequest.Body = tostring(HTTPS:JSONEncode(requestData)) end
	pcall(function()
		response = HTTPS:RequestAsync(builtRequest)
		script.HTTPCall:Fire(builtRequest)
		Data = HTTPS:JSONDecode(tostring(response.Body))
	end)
	if response.Success == false then warn("gildedRadio: Guilded's API servers rejected the request.") end
	return Data
end

--[[**
	Returns basic information about the server.
	
	@returns A table consisting of Guilded's Server model, populated with information on the channel you requested.
	
	For more information on how to read this table, see Guilded's API docs:
	
	https://www.guilded.gg/docs/api/servers/Server
**--]]
function gildedRadio.getServerInfo()
	local GuildedData = gildedRadio.internalMakeRequest(1,"servers/" ..servIDHolder)
	return GuildedData
end

--[[**
	Gets basic channel information for a single channel. Requires your bot's API token to have "Read Messages" permission for said channel.
	
	@param chanID[string,required] The internal ID of the channel you want information on.
	
	@returns A table consisting of Guilded's ServerChannel model, populated with information on the channel you requested.
	
	For more information on how to read this table, see Guilded's API docs:
	
	https://www.guilded.gg/docs/api/channels/ServerChannel
**--]]
function gildedRadio.getChannel(chanID:string)
	if not chanID then error("gildedRadio.getChannel: channel ID missing") end
	local GuildedData = gildedRadio.internalMakeRequest(1,"channels/" ..chanID)
	return GuildedData
end

--[[**
	Creates a chat channel in a server group. Requires your bot's API token to have "Create Channels" permission for your server or group.
	
	@param name[string,required,maxlen=100] The name of your new channel. Maximum length is 100, will warn and cut off if you feed more then 100 characters.
	@param topic[string,maxlen=512] The topic of your new channel, displays as a line of text along the top of the channel that users can click to read better. Pass 'nil' to leave empty.
	@param isPublic[bool] Whether or not the channel will be visible to @everyone.
	@param typeOfChannel[number,required] The type of channel to create:
	
	0: Announcements (for a group of users to read announcements)
	1: Chat (A regular text chat, like IRC or a Discord channel)
	2: Calendar (Mark significant events or post schedules)
	3: Forums (Post, reply to, and read topics like a regular forum)
	4: Media (Upload pictures and video)
	5: Docs (Write help documents using an interface slightly similar to Microsoft Word)
	6: Voice (A hub for people with microphones to communicate; one text channel included)
	7: List (A to-do list channel similar to, but not entirely like, Trello)
	8: Scheduling (A channel where people list times they're available)
	9: Stream (A single voice channel where people see each other's screens -- or cameras)
	@param groupID[string] The group the channel will be created in. If not provided, channel will appear at the server root instead.
	@param categoryID[number] The category the channel will be created under. If not provided, will appear as a top-level channel in the group or server root.
	
	@returns A table consisting of Guilded's ServerChannel model, populated with information on the channel you created.
	
	For more information on how to read this table, see Guilded's API docs:
	
	https://www.guilded.gg/docs/api/channels/ServerChannel
**--]]
function gildedRadio.makeChannel(name:string,topic:string,isPublic:boolean,typeOfChannel:number,groupID:string,categoryID:number)
	local channelData = {}
	if not name and not typeOfChannel then error("gildedRadio.makeChannel: incomplete channel information") else channelData.name = name end
	if topic then channelData.topic = topic end
	if isPublic then channelData.isPublic = isPublic end
	local tab = {[0]="announcements", [1]="chat",[2]="calendar",[3]="forums",[4]="media",[5]="docs",[6]="voice",[7]="list",[8]="scheduling",[9]="stream"}
	channelData["type"] = tab[typeOfChannel]
	if groupID then channelData.groupID = groupID end
	if categoryID then channelData.groupID = categoryID end
	local channelData = gildedRadio.internalMakeRequest(0,"channels",channelData)
	return channelData
end

--[[**
	Changes the name, topic, or publicity of a channel.
	
	@param name[string,required,maxlen=100] The new name of your channel. Maximum length is 100, will warn and cut off if you feed more then 100 characters.
	@param topic[string,maxlen=512] The new topic of your new channel, displays as a line of text along the top of the channel that users can click to read better. Pass 'nil' to leave empty.
	@param isPublic[bool,required] Whether or not the channel will be visible to @everyone.
	
	@returns A table consisting of Guilded's ServerChannel model, populated with information on the channel you created.
	
	For more information on how to read this table, see Guilded's API docs:
	
	https://www.guilded.gg/docs/api/channels/ServerChannel
**--]]
function gildedRadio.setChannel(name:string,topic:string,isPublic:boolean,groupID:string,categoryID:number)
	local channelData = {}
	if not name then error("gildedRadio.setChannel: incomplete channel information") else channelData.name = name end
	if topic then channelData.topic = topic end
	if isPublic then channelData.isPublic = true end
	if groupID then channelData.groupID = groupID end
	if categoryID then channelData.groupID = categoryID end
	local channelData = gildedRadio.internalMakeRequest(3,"channels/",channelData)
	return channelData
end
	
--[[**
	Deletes a channel.
	WARNING: Destructive action.
	
	@param chanID[string,required] The internal ID of the channel you want to delete.
**--]]
function gildedRadio.deleteChannel(chanID:string)
	if not chanID then error("gildedRadio.deleteChannel: channel ID missing") end
	gildedRadio.internalMakeRequest(4,"channels/" ..chanID)
end

--[[**
	Sends a text message to an Announcements, Chat, or Voice channel.
	If you want to create a message with an embed similar to bot messages from Discord, use the createEmbed function instead.
	
	@param chanID[string,required] The internal ID of the channel you want to send the message to.
	@param content[string,required,maxlen=4000] The message to send. Supports Markdown.
	@param isPrivate[bool] Whether or not this message is "private". If true, then users will only see this message if they or their role are mentioned.
	@param isSilent[bool] Whether or not this message will ping users. If false, then users will not be pinged, even if you mention them in this message.
	@param isReplyTo[string] Adds a message as a reply to someone earlier in the chain. Currently only supports a single message ID, although the Guilded API supports 5.
	
	@returns A table consisting of Guilded's ChatMessage model, populated with information from the message you just sent.
	
	More information on the ChatMessage model: https://www.guilded.gg/docs/api/chat/ChatMessage
**--]]
function gildedRadio.makeMessage(chanID:string,content:string,isPrivate:boolean,isSilent:boolean,isReplyTo:any)
	if not chanID or not content then error("gildedRadio.makeMessage: Missing channel ID or content") end
	local messageData = {}
	messageData.content = tostring(content)
	if isReplyTo then messageData.replyMessageIDs = {}
		messageData.replyMessageIDs[1] = isReplyTo
	end
	if isPrivate then messageData.isPrivate = true else messageData.isPrivate = false end
	if isSilent then messageData.isSilent = true end
	local GuildedData = gildedRadio.internalMakeRequest(0,"channels/" ..chanID.. "/messages", messageData)
	
	return GuildedData
end

--[[**
	Sends a text message to an Announcements, Chat, or Voice channel.
	This version lets you pass a table for the Embed function, but lacks the ability to reply. If you want to reply, use the createMessage function instead.
	
	@param chanID[string,required] The internal ID of the channel you want to send the message to.
	@param content[string,required,maxlen=4000] The message to send. Supports Markdown.
	@param embed[table,required] The embed you want to create. To use this parameter properly, please create a table based on the ChatEmbed model in Guilded's API:
	
	https://www.guilded.gg/docs/api/chat/ChatEmbed
	@param isPrivate[bool] Whether or not this message is "private". If true, then users will only see this message if they or their role are mentioned.
	@param isSilent[bool] Whether or not this message will ping users. If false, then users will not be pinged, even if you mention them in this message.
	
	@returns A table consisting of Guilded's ChatMessage model, populated with information from the message you just sent.
	
	More information on the ChatMessage model: https://www.guilded.gg/docs/api/chat/ChatMessage
**--]]
function gildedRadio.makeEmbed(chanID:string,content:string,isPrivate:boolean,isSilent:boolean,embed:any)
	if not chanID or not content or not embed then error("gildedRadio.makeEmbed: Missing channel ID, content, or embed") end
	local messageData = {}
	messageData.content = content
	messageData.embeds = {}
	messageData.embeds[1] = embed
	if isPrivate then messageData.isPrivate = true end
	if isSilent then messageData.isSilent = true end
	local GuildedData = gildedRadio.internalMakeRequest(0,"channels/" ..chanID.. "/messages", messageData)
	return GuildedData
end

--[[**
	Reads text messages from an Announcements, Chat, or Voice channel.
	
	@param chanID[string,required] The internal ID of the channel you want to read from.
	@param count[number,min=1,max=100] How many messages you want Guilded to return. Defaults to 10 if not specified, to keep API responses fast.
	@param before[string] Include an ISO 8601 timestamp as a string in this parameter, and Guilded will only send the most recent messages created before that date.
	@param includePrivate[boolean] Include private messages between users. Will error if set to true and your API token does not have the "Access Moderator View" permission.
	
	@returns A table consisting of multiple counts of Guilded's ChatMessage models, populated with information from the last X messages you requested.
	Messages will be ordered by their createdAt tag, which is an ISO 8601 timestamp.
	
	More information on the ChatMessage model: https://www.guilded.gg/docs/api/chat/ChatMessage
**--]]
function gildedRadio.getMessageBulk(chanID:string,count:number,before:string,includePrivate:boolean)
	if not chanID then error("gildedRadio.getMessageBulk: Missing channel ID") end
	local searchData = {}
	if count then searchData.limit = count else searchData.limit = 10 end
	if before then searchData.before = before end
	if includePrivate then searchData.includePrivate = true end
	local GuildedData = gildedRadio.internalMakeRequest(1,"channels/" ..chanID.. "/messages", searchData)
	return GuildedData
end

--[[**
	Reads a specific message from an Announcements, Chat, or Voice channel.
	
	@param chanID[string,required] The internal ID of the channel you want to read from.
	@param messageID[string,required] The ID of the message you want to read.
	
	@returns A table consisting of Guilded's ChatMessage model, populated with information from the message you requested.

	More information on the ChatMessage model: https://www.guilded.gg/docs/api/chat/ChatMessage
**--]]
function gildedRadio.getMessage(chanID:string,messageID:string)
	if not chanID or not messageID then error("gildedRadio.getMessage: Missing channel ID or message ID") end
	local GuildedData = gildedRadio.internalMakeRequest(1,"channels/" ..chanID.. "/messages/" ..messageID)
	return GuildedData
end

--[[**
	Edits a message that the bot your API token is controlling has sent.
	
	@param chanID[string,required] The internal ID of the channel your message is in.
	@param messageID[string,required] The ID of the message you want to edit.
	@param content[string,required] 
	
	@returns A table consisting of Guilded's ChatMessage model, populated with information from the message you requested.

	More information on the ChatMessage model: https://www.guilded.gg/docs/api/chat/ChatMessage
**--]]
function gildedRadio.setMessage(chanID:string,messageID:string,content:string,embed:any)
	if not chanID or not messageID or not content then error("gildedRadio.setMessage: Missing channel ID or message ID") end
	local messageData = {}
	messageData.content = content
	messageData.embeds = {}
	messageData.embeds[1] = embed
	local GuildedData = gildedRadio.internalMakeRequest(2,"channels/" ..chanID.. "/messages/" ..messageID)
	return GuildedData
end

--[[**
	Deletes a message.
	
	@param chanID[string,required] The internal ID of the channel the message is in.
	@param messageID[string,required] The ID of the message you want to remove.
	
	@returns A table consisting of Guilded's ChatMessage model, populated with only the ID from the message you requested.

	More information on the ChatMessage model: https://www.guilded.gg/docs/api/chat/ChatMessage
**--]]
function gildedRadio.deleteMessage(chanID:string,messageID:string)
	if not chanID or not messageID then error("gildedRadio.deleteMessage: Missing channel ID or message ID") end
	local GuildedData = gildedRadio.internalMakeRequest(5,"channels/" ..chanID.. "/messages/" ..messageID)
	return GuildedData
end

--[[**
	Get a list of members of your server. Note that this only returns member IDs and roles, not the names.
	
	@returns A table consisting of Guilded's ServerMemberSummary model, populated with information from the member list you requested.

	More information on the ServerMemberSummary model: https://www.guilded.gg/docs/api/members/ServerMemberSummary
**--]]
function gildedRadio.getMemberBulk()
	local GuildedData = gildedRadio.internalMakeRequest(1,"servers/" ..servIDHolder.. "/members")
	return GuildedData
end

--[[**
	Get information about a specific member of your server. This returns name, join date, roles, and other information.
	
	@param userID[string,required] The ID of the user you want information about.
	
	@returns A table consisting of Guilded's ServerMember model, populated with information from the member list you requested.

	More information on the ServerMember model: https://www.guilded.gg/docs/api/members/ServerMember
**--]]
function gildedRadio.getMember(userID: string)
	if not userID then error("gildedRadio.getMember: Missing user ID") end
	local GuildedData = gildedRadio.internalMakeRequest(1,"servers/" ..servIDHolder.. "/members/" ..userID)
	return GuildedData
end

--[[**
	Changes a member's nickname. Might be best to only use this with their permission.
	If you want to remove a nickname, use the deleteMemberNick function instead.
	
	@param userID[string,required] The ID of the user you want to update the nickname for.
	@param newNick[string,required] The username you're forcing upon their poor... I dunno, nametag? *shrug*
	
	@returns A table consisting of one string: The nickname assigned after your script reached Guilded.

	More information on the ServerMember model: https://www.guilded.gg/docs/api/members/ServerMember
**--]]
function gildedRadio.setMemberNick(userID: string,newNick: string)
	if not userID or not newNick then error("gildedRadio.updateMemberNick: Missing user ID") end
	local userData = {}
	userData.nickname = newNick
	local GuildedData = gildedRadio.internalMakeRequest(2,"servers/" ..servIDHolder.. "/members/" ..userID.. "/nickname")
	return GuildedData
end

--[[**
	Deletes a member's nickname. Might be best to only use this with their permission.
	If you want to replace a nickname, use the updateMemberNick function instead.
	
	@param userID[string,required] The ID of the user you want to remove the nickname for.
**--]]
function gildedRadio.deleteMemberNick(userID: string,newNick: string)
	if not userID or not newNick then error("gildedRadio.deleteMemberNick: Missing user ID") end
	local GuildedData = gildedRadio.internalMakeRequest(5,"servers/" ..servIDHolder.. "/members/" ..userID.. "/nickname")
	return GuildedData
end

--[[**
	Kicks a member from your server. He probably deserved it anyway.
	
	@param userID[string,required] The ID of the user you want to stop hearing from for a little bit.
**--]]
function gildedRadio.kickMember(userID: string)
	if not userID then error("gildedRadio.kickMember: Missing user ID") end
	local GuildedData = gildedRadio.internalMakeRequest(5,"servers/" ..servIDHolder.. "/members/" ..userID)
	return GuildedData
end

--[[**
	Bans a member from your server. He absolutely deserved it anyway.
	
	@param userID[string,required] The ID of the user you want to never, ever hear from again.
	
	@returns Returns a ServerMemberBan model populated with information from the ban you just created.
	
	More information on the ServerMemberBan model is available here: https://www.guilded.gg/docs/api/member-bans/ServerMemberBan
**--]]
function gildedRadio.createBan(userID: string)
	if not userID then error("gildedRadio.createBan: Missing user ID") end
	local GuildedData = gildedRadio.internalMakeRequest(0,"servers/" ..servIDHolder.. "/bans/" ..userID)
	return GuildedData
end

--[[**
	Gets a list of everyone you banned. In other words, the naughty list.
	
	@returns Returns a list a multiple ServerMemberBan models populated with information as needed.
	
	More information on the ServerMemberBan model is available here: https://www.guilded.gg/docs/api/member-bans/ServerMemberBan
**--]]
function gildedRadio.getBanBulk(userID: string)
	local GuildedData = gildedRadio.internalMakeRequest(1,"servers/" ..servIDHolder.. "/bans")
	return GuildedData
end

--[[**
	Gets a specific user you banned. In other words, your dear rival.
	
	@param userID[string,required] The ID of the user you want to never, hear from again.
	
	@returns Returns a ServerMemberBan model populated with information from the ban you just created.
	
	More information on the ServerMemberBan model is available here: https://www.guilded.gg/docs/api/member-bans/ServerMemberBan
**--]]
function gildedRadio.getBan(userID: string)
	if not userID then error("gildedRadio.createBan: Missing user ID") end
	local GuildedData = gildedRadio.internalMakeRequest(1,"servers/" ..servIDHolder.. "/bans/" ..userID)
	return GuildedData
end

--[[**
	Removes a ban, allowing said user back into your server. Guess they didn't deserve it that much.
	
	@param userID[string,required] The ID of the user you want to hear from again.
**--]]
function gildedRadio.deleteBan(userID: string)
	if not userID then error("gildedRadio.createBan: Missing user ID") end
	local GuildedData = gildedRadio.internalMakeRequest(5,"servers/" ..servIDHolder.. "/bans/" ..userID)
	return GuildedData
end

return gildedRadio
