--[[**
    Run gildedRadio.setup in your script to make the module ready to interact with your server. If the return value is anythiing that isn't 0, then either your authKey or serverID is incorrect.
    This module has extensive documentation! Install the Documentation Reader plugin to read the docs from inside Studio. https://devforum.roblox.com/t/documentation-reader-a-plugin-for-scripters/128825
    Track this plugin on Github: https://github.com/commandhat/cmdRobloxModules/edit/main/gildedRadio.lua
**--]]
local gildedRadio = {}
local authHolder = nil
local servIDHolder = nil
local retryBackoff = 0
local grBusy = false
local moduleVersion = "gildedRadio 0.2.1"
local robloxVersion = version()

--If you have a strict request budget or dislike request retries, change this to a 1. This can cause requests to fail on the first attempt, use with caution!
local noRetries = 0

--[[**
    Sets up the module to interact with a Guilded server. WARNING: Makes an HTTP request to verify Guilded connectivity.
    
    @param authKey[string,required] The authentication key used for your Guilded Bot. Make sure this is kept somewhere safe and private, like in ServerStorage!
    @param  serverID[string,required] The ID used for your server. Inside Guilded, enable Developer Mode, then right click your Server Icon on the left and click 'Copy Server ID.'
    
    @returns This function returns true if the module initialized successfully. If it returns false, something went wrong, check the console to learn what went wrong.
**--]]
function gildedRadio.setup(authKey: string,serverID: string,logCalls: boolean)
	authHolder = authKey
	servIDHolder = serverID
	local logCallObject = Instance.new("BindableEvent")
	logCallObject.Name = "HTTPSend"
	logCallObject.Parent = script
	local logCallObject2 = Instance.new("BindableEvent")
	logCallObject2.Name = "HTTPReceive"
	logCallObject2.Parent = script
	local resultData = gildedRadio.internalMakeRequest(5,"servers/" ..servIDHolder)
	if resultData then return true else return false end
end

--[[**
    This function is the module's HTTPService API wrapper. Please do not touch it. If you want to log gildedRadio requests, please read the documentation for gildedRadio.setup() instead.

	Note: This module uses a custom tag "X-Identity" to report library versioning. Guilded's library guidelines ask for a custom User-Agent, but that isn't possible at time of writing.
	The author of this library does not have the ability to create a relevant topic for this issue. If there is one available, create an issue on the module's Github with the topic link.
    
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
	if retryBackoff ~=0 then error("gildedRadio: In retry backoff mode. Please wait until isBusy returns false.")	end
	grBusy = true
	local HTTPS = game:GetService("HttpService")
	local baseUrl = "https://www.guilded.gg/api/v1/"
	local response
	local Data
	local builtRequest = {}
	local attempt = 0
	builtRequest.Url = baseUrl.. "" ..ApiURL
	local tab = {[0]="POST", [1]="GET",[2]="PUT",[3]="PATCH",[4]="DELETE",[5]="HEAD"}
	builtRequest.Method = tab[mode]
	builtRequest.Headers = {}
	local fixedString = "Bearer " ..authHolder
	builtRequest.Headers["Accept"] = "application/json"
	builtRequest.Headers["Content-type"] = "application/json"
	builtRequest.Headers["X-Secondary-User-Agent"] = moduleVersion.. " on Roblox " ..robloxVersion
	if requestData ~= nil then builtRequest.Body = tostring(HTTPS:JSONEncode(requestData)) end
	builtRequest.Headers["Authorization"] = "**REMOVED**"

	builtRequest.Headers["Authorization"] = fixedString
	repeat
		if retryBackoff ~=0 then repeat wait(1) retryBackoff = retryBackoff - 1 until retryBackoff == 0 end
		pcall(function()
			response = HTTPS:RequestAsync(builtRequest)
			Data = HTTPS:JSONDecode(tostring(response.Body))
			script.HTTPSend:Fire(builtRequest)
		end)
		if response.Success == false then warn("gildedRadio: Guilded's API rejected the request.")
		attempt = attempt + 1
		retryBackoff = attempt^2
		end
	until response.Success or attempt == 8 or noRetries == 1
	if attempt == 8 then warn("gildedRadio: Guilded's API is down, or unreachable after 7 attempts with exponential backoff. If a response was received, it will be sent to HTTPReceive now.") end
	script.HTTPReceive:Fire(response)
	retryBackoff = 0
	grBusy = false
	return Data
end

--[[**
    Helper function to allow the creation of queues.

	@returns true if the API is busy with a request at the moment of calling (most likely exponential backoff). False if the API is not busy (open to requests).
**--]]
function gildedRadio.isBusy()
	if grBusy then return true else return false end
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
	if not name or not typeOfChannel then error("gildedRadio.makeChannel: incomplete channel information") else channelData.name = name end
	if topic then channelData.topic = topic end
	if isPublic then channelData.isPublic = true elseif isPublic ~= nil then channelData.isPublic = false end
	local tab = {[0]="announcements", [1]="chat",[2]="calendar",[3]="forums",[4]="media",[5]="docs",[6]="voice",[7]="list",[8]="scheduling",[9]="stream"}
	channelData["type"] = tab[typeOfChannel]
	if groupID then channelData.groupID = groupID end
	if categoryID then channelData.groupID = categoryID end
	local channelData = gildedRadio.internalMakeRequest(0,"channels",channelData)
	return channelData
end

--[[**
	Changes the name, topic, or publicity of a channel.
	
	@param chanID[string,required]
	@param name[string,maxlen=100] The new name of your channel. Maximum length is 100, will warn and cut off if you feed more then 100 characters.
	@param topic[string,maxlen=512] The new topic of your new channel, displays as a line of text along the top of the channel that users can click to read better. Pass 'nil' to leave empty.
	@param isPublic[bool,required] Whether or not the channel will be visible to @everyone.
	
	@returns A table consisting of Guilded's ServerChannel model, populated with information on the channel you created.
	
	For more information on how to read this table, see Guilded's API docs:
	
	https://www.guilded.gg/docs/api/channels/ServerChannel
**--]]
function gildedRadio.setChannel(chanID:string,name:string,topic:string,isPublic:boolean,groupID:string,categoryID:number)
	local channelData = {}
	if not chanID then error("gildedRadio.setChannel: missing channel ID") end
	if not name and not topic and not groupID and not categoryID and isPublic == nil then error("gildedRadio.setChannel: no content detected, not updating.") end
	if name then channelData.name = name end
	if topic then channelData.topic = topic end
	if isPublic then channelData.isPublic = true elseif isPublic ~= nil then channelData.isPublic = false end
	if groupID then channelData.groupID = groupID end
	if categoryID then channelData.groupID = categoryID end
	local channelData = gildedRadio.internalMakeRequest(3,"channels/" ..chanID,channelData)
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
	@param count[number,max=100] How many messages you want Guilded to return. Defaults to 10 if not specified, to keep API responses fast.
	@param before[string] Include an ISO 8601 timestamp as a string in this parameter, and Guilded will only send the most recent messages created before that date.
	@param includePrivate[boolean] Include private messages between users. Will error if set to true and your API token does not have the "Access Moderator View" permission.
	
	@returns A table consisting of multiple counts of Guilded's ChatMessage models, populated with information from the most recent X messages you requested.
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
	Edits a message that the bot your API token is controlling has sent. Can also edit embedded messages.
	
	@param chanID[string,required] The internal ID of the channel your message is in.
	@param messageID[string,required] The ID of the message you want to edit.
	@param content[string,oneof] The new content of the message you are editing.
	@param embed[table,oneof] The new content of the message's embed. Can be used to add an embed to an existing message.
	
	@returns A table consisting of Guilded's ChatMessage model, populated with information from the message you requested.

	More information on the ChatMessage model: https://www.guilded.gg/docs/api/chat/ChatMessage
**--]]
function gildedRadio.setMessage(chanID:string,messageID:string,content:string,embed:any)
	if not chanID or not messageID then error("gildedRadio.setMessage: Missing channel ID or message ID") end
	if not content and not embed then error("gildedRadio.setMessage: both content and embed are empty, nothing to update") end
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
	local GuildedData = gildedRadio.internalMakeRequest(4,"channels/" ..chanID.. "/messages/" ..messageID)
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
	local GuildedData = gildedRadio.internalMakeRequest(4,"servers/" ..servIDHolder.. "/members/" ..userID.. "/nickname")
	return GuildedData
end

--[[**
	Kicks a member from your server. He probably deserved it anyway.
	
	@param userID[string,required] The ID of the user you want to stop hearing from for a little bit.
**--]]
function gildedRadio.kickMember(userID: string)
	if not userID then error("gildedRadio.kickMember: Missing user ID") end
	local GuildedData = gildedRadio.internalMakeRequest(4,"servers/" ..servIDHolder.. "/members/" ..userID)
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
	gildedRadio.internalMakeRequest(4,"servers/" ..servIDHolder.. "/bans/" ..userID)
end

--[[**
	Awards XP to a specific member. Give them a shot of happiness for something!
	
	@param userID[string,required] The ID of the user you want to reward.
	@param incomingXp[number,required] The XP you're giving them.

	@returns Returns a table with one member: "total", containing the new XP amount they have.
**--]]
function gildedRadio.awardXP(userID: string,incomingXp: number)
	if not userID or not incomingXp then error("gildedRadio.awardXP: Missing user ID or XP number") end
	local GuildedData = gildedRadio.internalMakeRequest(0,"servers/" ..servIDHolder.. "/members/" ..userID.. "/xp")
	return GuildedData
end

--[[**
	Awards XP to everyone with a specific role. Got a clan that just won a major war? This is for them.
	WARNING: This function does not return, because Guilded does not return any results after this operation.
	
	@param roleID[string,required] The ID of the role you want to reward.
	@param incomingXp[number,required] The XP you're giving them.
**--]]
function gildedRadio.awardXPBulk(roleID: string,incomingXp: number)
	if not roleID or not incomingXp then error("gildedRadio.awardXP: Missing role ID or XP number") end
	gildedRadio.internalMakeRequest(0,"servers/" ..servIDHolder.. "/roles/" ..roleID.. "/xp")
end

--[[**
	Sets XP directly for aspecific member. Maybe you gave them a little too much happiness...
	
	@param userID[string,required] The ID of the user you want to edit.
	@param incomingXp[number,required] The XP count you want them to have.

	@returns Returns a table with one member: "total", containing the new XP amount they have.
**--]]
function gildedRadio.setXP(userID: string,incomingXp: number)
	if not userID or not incomingXp then error("gildedRadio.setXP: Missing user ID or XP number") end
	local GuildedData = gildedRadio.internalMakeRequest(2,"servers/" ..servIDHolder.. "/members/" ..userID.. "/xp")
	return GuildedData
end

--[[**
	Get all the roles assigned to a particular member.
	
	@param userID[string,required] The ID of the user you want to inspect.

	@returns Returns a table of integers. Each integer is the ID for a given role.
**--]]
function gildedRadio.getRoles(userID: string)
	if not userID then error("gildedRadio.getRoles: Missing user ID") end
	local GuildedData = gildedRadio.internalMakeRequest(1,"servers/" ..servIDHolder.. "/members/" ..userID.. "/roles")
	return GuildedData
end

--[[**
	Add a role to someone's membership set.
	
	@param userID[string,required] The ID of the user you want to add the role to.
	@param roleID[number,required] The ID of the role you want to give them.
**--]]
function gildedRadio.setRole(userID: string,roleID: string)
	if not userID or not roleID then error("gildedRadio.setRole: Missing user ID or role ID") end
	local GuildedData = gildedRadio.internalMakeRequest(2,"servers/" ..servIDHolder.. "/members/" ..userID.. "/roles/" ..roleID)
	return GuildedData
end

--[[**
	Force someone to turn in their membership card for a given role.
	
	@param userID[string,required] The ID of the user you want to punish.
	@param roleID[number,required] The ID of the role you want to shrink.
**--]]
function gildedRadio.deleteRole(userID: string,roleID: string)
	if not userID or not roleID then error("gildedRadio.deleteRole: Missing user ID or role ID") end
	local GuildedData = gildedRadio.internalMakeRequest(4,"servers/" ..servIDHolder.. "/members/" ..userID.. "/roles/" ..roleID)
end

--[[**
	Join someone to a group in your server.
	
	@param userID[string,required] The ID of the user you want to audit.
	@param groupID[number,required] The ID of the group to add them to.
**--]]
function gildedRadio.setGroup(userID: string,groupID: string)
	if not userID or not groupID then error("gildedRadio.setGroup: Missing user ID or group ID") end
	local GuildedData = gildedRadio.internalMakeRequest(2,"groups/" ..groupID.. "/members/" ..userID)
	return GuildedData
end

--[[**
	Remove someone from a group in your server.
	
	@param userID[string,required] The ID of the user you want to audit.
	@param groupID[number,required] The ID of the group to take away from.
**--]]
function gildedRadio.removeGroup(userID: string,groupID: string)
	if not userID or not groupID then error("gildedRadio.removeGroup: Missing user ID or group ID") end
	gildedRadio.internalMakeRequest(4,"groups/" ..groupID.. "/members/" ..userID)
end

--[[**
	Reads topics in bulk from a Forum channel.
	
	@param chanID[string,required] The internal ID of the channel you want to read from.
	@param count[number,max=100] How many topics you want Guilded to return. Defaults to 10 if not specified, to keep API responses fast.
	@param before[string] Include an ISO 8601 timestamp as a string in this parameter, and Guilded will only send the most recent messages created before that date.
	
	@returns A table consisting of Guilded's FroumTopicSummary model, populated with information from the most recent X topics you requested.
	Topics will be ordered by their createdAt tag, which is an ISO 8601 timestamp.
	
	More information on the ChatMessage model: https://www.guilded.gg/docs/api/forums/ForumTopicSummary
**--]]
function gildedRadio.getTopicBulk(chanID:string,count:number,before:string)
	if not chanID then error("gildedRadio.getMessageBulk: Missing channel ID") end
	local searchData = {}
	if count then searchData.limit = count else searchData.limit = 10 end
	if before then searchData.before = before end
	local GuildedData = gildedRadio.internalMakeRequest(1,"channels/" ..chanID.. "/topic", searchData)
	return GuildedData
end

--[[**
	Reads a specific topic from a Forum channel.
	
	@param chanID[string,required] The internal ID of the channel you want to read from.
	@param topicID[string,required] The internal ID of the forum topic you're reading.
	
	@returns A table consisting of Guilded's ForumTopic model, populated with information from the first post in the topic (also called Original Post or OP).
	Messages will be ordered by their createdAt tag, which is an ISO 8601 timestamp.
	
	More information on the ForumTopic model: https://www.guilded.gg/docs/api/forums/ForumTopic
**--]]
function gildedRadio.getTopic(chanID:string,topicID:string)
	if not chanID or not topicID then error("gildedRadio.getTopic: Missing channel ID or topic ID") end
	local GuildedData = gildedRadio.internalMakeRequest(1,"channels/" ..chanID.. "/topics/".. topicID)
	return GuildedData
end

--[[**
	Updates the first post in a topic in a Forum channel, if it's controlled by your bot.
	
	@param chanID[string,required] The internal ID of the channel you want to read from.
	@param topicID[string,required] The internal ID of the forum topic you're editing.
	@param title[string,maxlen=500] The new name of the topic.
	@param content[string,maxlen=4000] The new content of the first post in the topic.
	
	@returns A table consisting of Guilded's ForumTopic model, populated with information from the first post in the topic (also called Original Post or OP).
	Messages will be ordered by their createdAt tag, which is an ISO 8601 timestamp.
	
	More information on the ForumTopic model: https://www.guilded.gg/docs/api/forums/ForumTopic
**--]]
function gildedRadio.updateTopic(chanID:string,topicID:string,title:string,content:string)
	if not chanID then error("gildedRadio.updateTopic: Missing channel ID or topic ID") end
	if not title or content then error("gildedRadio.updateTopic: No content detected, nothing to update") end
	local GuildedData = gildedRadio.internalMakeRequest(3,"channels/" ..chanID.. "/topics/".. topicID)
	return GuildedData
end

--[[**
	Delete a specific topic from a Forum channel.
	
	@param chanID[string,required] The internal ID of the channel you want to edit.
	@param topicID[string,required] The internal ID of the forum topic you're removing.
**--]]
function gildedRadio.deleteTopic(chanID:string,topicID:string)
	if not chanID or not topicID then error("gildedRadio.deleteTopic: Missing channel ID or topic ID") end
	gildedRadio.internalMakeRequest(4,"channels/" ..chanID.. "/topics/".. topicID)
end

--[[**
	Pin a topic to the top of a Forum channel. The name is a consequence of matching function names with actions.
	
	@param chanID[string,required] The internal ID of the channel you want to manipulate.
	@param topicID[string,required] The internal ID of the forum topic you're pinning.
**--]]
function gildedRadio.makeTopicPin(chanID:string,topicID:string)
	if not chanID or not topicID then error("gildedRadio.makeTopicPin: Missing channel ID or topic ID") end
	gildedRadio.internalMakeRequest(2,"channels/" ..chanID.. "/topics/" ..topicID.. "/pin")
end

--[[**
	Unpin a topic to the top of a Forum channel. The name is a consequence of matching function names with actions.
	
	@param chanID[string,required] The internal ID of the channel you want to manipulate.
	@param topicID[string,required] The internal ID of the forum topic you're pinning.
**--]]
function gildedRadio.deleteTopicPin(chanID:string,topicID:string)
	if not chanID or not topicID then error("gildedRadio.deleteTopicPin: Missing channel ID or topic ID") end
	gildedRadio.internalMakeRequest(4,"channels/" ..chanID.. "/topics/" ..topicID.. "/pin")
end

--[[**
	Lock a forum topic, preventing replies from anyone except those with moderator permissions. The name is a consequence of matching function names with actions.
	
	@param chanID[string,required] The internal ID of the channel you want to manipulate.
	@param topicID[string,required] The internal ID of the forum topic you're pinning.
**--]]
function gildedRadio.makeTopicLock(chanID:string,topicID:string)
	if not chanID or not topicID then error("gildedRadio.makeTopicLock: Missing channel ID or topic ID") end
	gildedRadio.internalMakeRequest(2,"channels/" ..chanID.. "/topics/" ..topicID.. "/lock")
end

--[[**
	Unlock a forum topic, allowing replies from anyone with appropriate permission. The name is a consequence of matching function names with actions.
	
	@param chanID[string,required] The internal ID of the channel you want to manipulate.
	@param topicID[string,required] The internal ID of the forum topic you're pinning.
**--]]
function gildedRadio.deleteTopicLock(chanID:string,topicID:string)
	if not chanID or not topicID then error("gildedRadio.deleteTopicLock: Missing channel ID or topic ID") end
	gildedRadio.internalMakeRequest(4,"channels/" ..chanID.. "/topics/" ..topicID.. "/lock")
end

--[[**
	Reads a specific topic from a Forum channel.
	
	@param chanID[string,required] The internal ID of the channel you want to read from.
	@param topicID[string,required] The internal ID of the forum topic you're reading.
	
	@returns A table consisting of Guilded's ForumTopic model, populated with information from the first post in the topic (also called Original Post or OP).
	Messages will be ordered by their createdAt tag, which is an ISO 8601 timestamp.
	
	More information on the ForumTopic model: https://www.guilded.gg/docs/api/forums/ForumTopic
**--]]
function gildedRadio.getTopicReplyBulk(chanID:string,topicID:string)
	if not chanID or not topicID then error("gildedRadio.getTopicReplyBulk: Missing channel ID or topic ID") end
	local GuildedData = gildedRadio.internalMakeRequest(1,"channels/" ..chanID.. "/topics/"..topicID.. "/comments")
	return GuildedData
end

--[[**
	Reads a specific reply to a topic from a Forum channel.
	
	@param chanID[string,required] The internal ID of the channel you want to read from.
	@param topicID[string,required] The internal ID of the forum topic you're reading.
	@param replyID[string,required] The internal ID of the specific reply you want to read.
	
	@returns A table consisting of Guilded's ForumTopicComment model, populated with information from the reply you requested.
	Messages will be ordered by their createdAt tag, which is an ISO 8601 timestamp.
	
	More information on the ForumTopic model: https://www.guilded.gg/docs/api/forums/ForumTopicComment
**--]]
function gildedRadio.getTopicReply(chanID:string,topicID:string,replyID:string)
	if not chanID or not topicID or not replyID then error("gildedRadio.getTopicReply: Missing channel ID, topic ID, or reply ID") end
	local GuildedData = gildedRadio.internalMakeRequest(1,"channels/" ..chanID.. "/topics/"..topicID.. "/comments/" ..replyID)
	return GuildedData
end

--[[**
	Replies to a topic in a Forum channel.
	
	@param chanID[string,required] The internal ID of the channel you want to read from.
	@param topicID[string,required] The internal ID of the forum topic you're reading.
	@param content[string,required,maxlen=4000] The content of the reply you're making.
	
	@returns A table consisting of Guilded's ForumTopicComment model, populated with information from the reply you created.
	Messages will be ordered by their createdAt tag, which is an ISO 8601 timestamp.
	
	More information on the ForumTopic model: https://www.guilded.gg/docs/api/forums/ForumTopicComment
**--]]
function gildedRadio.makeTopicReply(chanID:string,topicID:string,content:string)
	if not chanID or not topicID  then error("gildedRadio.getTopicReply: Missing channel ID or topic ID") end
	local replyData = {}
	replyData.content = content
	local GuildedData = gildedRadio.internalMakeRequest(0,"channels/" ..chanID.. "/topics/"..topicID.. "/comments", replyData)
	return GuildedData
end

--[[**
	Updates a topic reply you made via bot.
	
	@param chanID[string,required] The internal ID of the channel you want to read from.
	@param topicID[string,required] The internal ID of the forum topic you're reading.
	@param replyID[string,required] The internal id of the reply you want to edit.
	@param content[string,required,maxlen=4000] The content of the reply you're making.
	
	@returns A table consisting of Guilded's ForumTopicComment model, populated with information from the reply you requested.
	Messages will be ordered by their createdAt tag, which is an ISO 8601 timestamp.
	
	More information on the ForumTopic model: https://www.guilded.gg/docs/api/forums/ForumTopicComment
**--]]
function gildedRadio.setTopicReply(chanID:string,topicID:string,replyID:string,content:string)
	if not chanID or not topicID then error("gildedRadio.setTopicReply: Missing channel ID or topic ID") end
	if not content then error("gildedRadio.setTopicReply: no content detected, not updating.") end
	local replyData = {}
	replyData.content = content
	local GuildedData = gildedRadio.internalMakeRequest(3,"channels/" ..chanID.. "/topics/"..topicID.. "/comments", replyData)
	return GuildedData
end

--[[**
	Deletes a topic reply from a Forum channel.
	
	@param chanID[string,required] The internal ID of the channel you want to read from.
	@param topicID[string,required] The internal ID of the forum topic you're reading.
	@param replyID[string,required] The internal ID of the specific reply you want to delete.
**--]]
function gildedRadio.deleteTopicReply(chanID:string,topicID:string,replyID:string)
	if not chanID or not topicID or not replyID then error("gildedRadio.deleteTopicReply: Missing channel ID, topic ID, or reply ID") end
	gildedRadio.internalMakeRequest(4,"channels/" ..chanID.. "/topics/"..topicID.. "/comments/" ..replyID)
end

return gildedRadio
