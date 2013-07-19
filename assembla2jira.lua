#!/usr/local/bin/lua

--[[
-- =====================================================================

Copyright (c) 2012 Anton Breusov

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the "Software"),
to deal in the Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom
the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included
in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH
THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

-- =====================================================================
--]]

-- =====================================================================
--
-- assembla2jira Version: 1.0
-- http://code.google.com/p/assembla2jira/
--
-- =====================================================================

-- =====================================================================
-- =====================================================================
--
-- Modules.
--
-- =====================================================================
-- =====================================================================

-- We use libYAML binding for Lua ( http://yaml.luaforge.net/index.html )
-- This is C (binary) LUA library and needs to be built and put to LUA pathes
-- or in directory where this script is located.
-- 
-- Read documentation on 'require()' function in LUA Reference Manual for more details.
require("yaml")

-- We use jfJSON by Jeffrey Friedl ( http://regex.info/blog/ )
-- NOTE that we using our patched version with explicit JSON null support in arrays,
-- it's shipped with this script.
-- Contributed version (20111207.5) will not work!

JSON = (loadfile "JSON.lua")()

-- =====================================================================
-- =====================================================================
--
-- Global service functions.
--
-- =====================================================================
-- =====================================================================

-- ---------------------------------------------------------------------
-- xmlEscape.
-- 
-- Do standard and required XML escapes: &, ', ", <, > .
-- ---------------------------------------------------------------------

function xmlEscape(str)
	local s = string.gsub(str, "&", "&amp;")
	s = string.gsub(s, "'", "&apos;")
	s = string.gsub(s, "\"", "&quot;")
	s = string.gsub(s, "<", "&lt;")
	s = string.gsub(s, ">", "&gt;")
	return s
end

-- ---------------------------------------------------------------------
-- xmlWriteIndent.
-- 
-- Writes required number of tabs characters for indenting tags.
-- ---------------------------------------------------------------------

function xmlWriteIndent(outFile, indent)
	if (indent > 0) then
		for i = 1,indent do
			outFile:write("\t")
		end
	end
end

-- ---------------------------------------------------------------------
-- xmlDump.
--
-- Dumps specified xmlTree into outFile as XML.
-- ---------------------------------------------------------------------

function xmlDump(outFile, xmlTree, visited)
	local visited = { }
	local indent = 0
	if (xmlTree.name ~= nil) then
		outFile:write ("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n")
		xmlDumpTag(outFile, xmlTree, indent, visited)
		return true
	end
	return false
end

-- ---------------------------------------------------------------------
-- xmlDumpTag.
--
-- Internal function for xmlDump, writes single XML tag to file (recursively).
-- Can handle cyclic reference in lua onjects (via visited container).
-- ---------------------------------------------------------------------

function xmlDumpTag(outFile, tag, indent, visited)
	if (visited[tag] == nil) then
		visited[tag] = true
		if (tag.text ~= nil) then
			xmlWriteIndent(outFile, indent)
			outFile:write(xmlEscape(tag.text))
			outFile:write("\n")
		elseif (tag.name ~= nil) then
			xmlWriteIndent(outFile, indent)
			if (tag.attrs ~= nil) then
				outFile:write("<", tag.name)
				for n,v in pairs(tag.attrs) do
					outFile:write(" ", n, "=\"", xmlEscape(v), "\"")
				end
			else
				outFile:write("<", tag.name)
			end

			if (tag.tags ~= nil) then
				outFile:write(">\n")

				for _,t in ipairs(tag.tags) do
					xmlDumpTag(outFile, t, indent + 1, visited)
				end

				xmlWriteIndent(outFile, indent)
				outFile:write("</", tag.name, ">\n")
			else
				outFile:write("/>\n")
			end

		end
	end
end

-- ---------------------------------------------------------------------
-- xmlCreateTag.
--
-- Creates XML tag object.
-- ---------------------------------------------------------------------

function xmlCreateTag (name)
	local matchStart = string.find (name, "[^%a:%-_]")
	assert(matchStart == nil)

	local tag = { }
	tag.name = name
	return tag
end

-- ---------------------------------------------------------------------
-- xmlAppendTag.
--
-- Appends XML tag to other XML tag, at the end of list.
-- ---------------------------------------------------------------------

function xmlAppendTag (tag, subTag)
	assert(tag ~= nil)
	assert(type(tag) == "table")
	assert(tag.name ~= nil)
	assert(type(subTag) == "table")

	if (tag.tags == nil) then
		tag.tags = { }
	end

	table.insert (tag.tags, subTag)

	return tag
end

-- ---------------------------------------------------------------------
-- xmlAppendTextTag.
--
-- Not implemented.
-- ---------------------------------------------------------------------

--[[
function xmlAppendTextTag (tag, text)
end
--]]

-- ---------------------------------------------------------------------
-- xmlSetAttr.
--
-- Sets attribute value (must be string) to XML tag.
-- Old value is ovewritten.
-- ---------------------------------------------------------------------

function xmlSetAttr (tag, attrName, attrValue)
	assert(tag ~= nil)
	assert(type(tag) == "table")
	assert(tag.name ~= nil)
	assert(type(attrName) == "string")
	assert(type(attrValue) == "string")

	local matchStart = string.find (attrName, "[^%a:%-_]")
	assert(matchStart == nil)

	if (tag.attrs == nil) then
		tag.attrs = { }
	end

	tag.attrs[attrName] = attrValue

	return tag
end

-- ---------------------------------------------------------------------
-- jellyEscape.
--
-- Performs escapes for Jelly special symbols ($) that marks variable substitution.
-- ---------------------------------------------------------------------

function jellyEscape(str)
	assert(type(str) == "string")

	local s,n = string.gsub (str, "%$", "%$%$")
	return s
end

-- =====================================================================
-- =====================================================================
--
-- Data.
--
-- =====================================================================
-- =====================================================================

-- ---------------------------------------------------------------------
-- Define any Constants
-- ---------------------------------------------------------------------

const = { }

const.errorCodes = { }

const.errorCodes.noError = 0
const.errorCodes.invalidArgs = 1
const.errorCodes.cannotOpenDump = 2

-- This tables will be ignored right when parsing dump file,
-- it reduces size of processed data.
const.ignoreTables =
{
	"user_roles", "wiki_pages", "scrum_reports",
	"time_logs", "brandings", "job_agreements", "job_postings",
	"job_responses", "job_statements", "flows", "wiki_page_versions",
	"drawings", "job_agreement_comments", "job_messages",
	"messages", "estimate_histories", "tasks", "ticket_reports",
	"documents", "document_versions",
}

-- When parsing input file schema, we require this fields to be present.
-- Note that fields that are not specified here will not be put into
-- parsed DB table, so if you want to use some field later, you should specify it here.

const.requiredFields =
{
	["spaces"] =
	{
		"id", "name", "description", "wiki_name", "created_at", "updated_at", "payer_id",
	},

	["milestones"] =
	{
		"id", "due_date", "title", "user_id", "created_at", "created_by", "space_id",
		"description", "is_completed", "completed_date",
		"updated_at", "updated_by",
	},

	["space_tools"] =
	{
		"id", "space_id", "active", "url", "tool_id", "type"
	},

	["ticket_statuses"] =
	{
		"id", "space_tool_id", "name", "state", "list_order", "created_at", "updated_at"
	},

	["tickets"] =
	{
		"id", "number", "reporter_id", "assigned_to_id", "space_id",
		"summary", "priority", "description", "created_on", "updated_at",
		"milestone_id", "component_id", "completed_date",
		"importance", "ticket_status_id", "state",
	},

	["ticket_comments"] =
	{
		"id", "ticket_id", "user_id", "created_on", "updated_at", "comment", "ticket_changes",
	},

	["workflow_property_defs"] =
	{
		"id", "space_tool_id", "type", "title", "order", "required",
		"hide", "created_at", "updated_at", "default_value",
	},

	["workflow_property_vals"] =
	{
		"id", "workflow_instance_id", "space_tool_id", "workflow_property_def_id", "value"
	},

	["ticket_associations"] =
	{
		"id", "ticket1_id", "ticket2_id", "relationship", "created_at"
	},

	["users"] =
	{
		"id", "login"
	},
}

-- This table will be used for mapping Assembla field names
-- in 'comment changes' structure if this table is not specified
-- in settings.lua file. Otherwise we will use table from settings.lua .

const.commentChanges =
{
	["assigned_to_id"] =
	{
		["name"] = "Assigned to",
	},

	["status"] =
	{
		["name"] = "Status",
	},

	["milestone_id"] =
	{
		["name"] = "Milestone",
	},

	["priority"] =
	{
		["name"] = "Priority",
	},

	["total_working_hours"] =
	{
		["name"] = "Total Working Hours",
	},

	["working_hours"] =
	{
		["name"] = "Working Hours",
	},

	["component_id"] =
	{
		["name"] = "Component",
	},

	["description"] =
	{
		["name"] = "Description",
	},

	["summary"] =
	{
		["name"] = "Summary",
	},
}

-- =====================================================================
-- =====================================================================
--
-- Functions.
--
-- =====================================================================
-- =====================================================================

-- ---------------------------------------------------------------------
-- getSettingsTable.
-- 
-- queries settings table from settings.lua file for
-- table and key. Returns found mapping or nil.
-- ---------------------------------------------------------------------

function getSettingsTable(tableName, keyName)
	if (settings ~= nil) then
		local t = settings[tableName]
		if (t ~= nil) then
			return t[keyName]
		end
	end
	return nil
end

-- ---------------------------------------------------------------------
-- isTableIgnored.
--
-- Checks, if some table in dump file should be ignored.
-- ---------------------------------------------------------------------

function isTableIgnored(ignoreList, tableName)
	for k,v in ipairs(ignoreList) do
		if (v == tableName) then
			return true
		end
	end
	return false
end

-- ---------------------------------------------------------------------
-- getUserMapping.
-- 
-- Service function that helps with mapping between Assembla and Jira users.
-- Returns mapping table, not user name.
-- ---------------------------------------------------------------------

function getUserMapping(login)
	local userMapping = getSettingsTable("users", login)
	if (userMapping == nil) then
		return error (string.format ("Missing mapping for user login \"%s\" in settings file", login), 0)
	end

	if (userMapping.username == nil) then
		return error (string.format ("Missing required field \"username\" in mapping for user login \"%s\" in settings file", login), 0)
	end

	return userMapping
end

-- ---------------------------------------------------------------------
-- mapUserName.
--
-- Wrapper over getUserMapping to return username.
-- ---------------------------------------------------------------------

function mapUserName(login)
	return getUserMapping(login).username
end

-- ---------------------------------------------------------------------
-- parseFile.
--
-- Performs parsing of Assembla dump file. Returns parsed database.
-- ---------------------------------------------------------------------

function parseFile(inFile)
	assert(inFile ~= nil)

	local db = { }

	db.schemas = { }
	db.tables = { }

	local unknownTables = { }
	local duplicatedTables = { }
	local discoveredTables = { }

	local line = nil
	local lineNumber = 0
	repeat
		line = inFile:read()
		if (line == nil) then
			break
		end

		lineNumber = lineNumber + 1

		local lineLength = string.len(line)
		if (lineLength > 0) then
			-- Split string according to format: "tableName[:fields], \[JSONField, JSONField, ...\] "
			local matchStart, matchEnd, tableName, schemaTag, tableRow =
				-- old parser
				-- string.find (line, "^([a-z_]+)(:?[a-z]*)%s*,%s*(%[.+])$")
				-- new parser
				string.find (line, "^([a-z_]+)(:?[a-z]*)%s*,%s*([%[%{].+[%]%}])$")

			-- print (lineLength, matchStart, matchEnd, tableName, fieldContents)

			matchStart = tonumber(matchStart)
			matchEnd = tonumber(matchEnd)

			if (matchStart == nil or
				matchStart > 1 or
				matchEnd == nil or
				matchEnd ~= lineLength or
				tableName == nil or
				tableRow == nil)
			then
				return error (string.format ("Error parsing line %d \"%s\"", lineNumber, line), 0)
			end

			-- Do JSON parsing.
			local rowData = JSON:decode (tableRow)
			if (rowData == nil) then
				return error (string.format ("Invalid JSON data on line %d: \"%s\"", lineNumber, rowData), 0)
			end

			if (schemaTag ~= nil and string.len(schemaTag) > 0) then
				-- It's a table schema.
				if (schemaTag ~= ":fields") then
					return error (string.format ("Error parsing line %d \"%s\"", lineNumber, line), 0)
				end

				local duplicated = false
				-- if schema for this table already exist we ignore it for avoid multiple schema definition into assembla export
				if (isTableIgnored(discoveredTables, tableName) == true) then
					if (isTableIgnored(duplicatedTables, tableName) == false) then
						print (string.format ("Info: duplicate schema for table \"%s\", it will be ignored", tableName))
						table.insert (duplicatedTables, tableName)
					end
					duplicated = true
				end

				-- Check, if we should ignore this table.
				local ignored = isTableIgnored(const.ignoreTables, tableName)

				if (ignored ~= false or duplicated  ~= false) then
					if (duplicated  ~= true) then
						print (string.format ("Info: ignoring table \"%s\"", tableName))
					end
				else
					local reqFields = const.requiredFields[tableName]

					if (reqFields == nil) then
						-- Issue warning (but only one time).
						if (isTableIgnored(unknownTables, tableName) == false) then
							print (string.format ("Warning: unknown table \"%s\", ignoring it.", tableName))
							table.insert (unknownTables, tableName)
						end
					else
						print (string.format ("Info: processing table \"%s\"", tableName))

						-- Now, analyze if all field names are strings.
						for k,v in pairs(rowData) do
							if (type(k) ~= "number" or type(v) ~= "string") then
								return error (string.format ("Error analyzing table fields at line %d: \"%s\" should be string value", lineNumber, v), 0)
							end

						end

						-- Check that all required fields are present.
						for _,j in ipairs(reqFields) do
							local found = false
							for _,v in pairs(rowData) do
								if (j == v) then
									found = true
									break
								end
							end

							if (found == false) then
								return error (string.format ("Error analyzing table fields at line %d: missing required field \"%s\" in table \"%s\"", lineNumber, j, tableName), 0)
							end
						end

						db.schemas[tableName] = rowData
						db.tables[tableName] = { }
					end
				end
				table.insert (discoveredTables, tableName)
			else
				-- Check, if we should ignore this table.
				local ignored = (isTableIgnored(const.ignoreTables, tableName) or isTableIgnored(unknownTables, tableName))
				if (ignored == false) then
					-- It's a table line.
					local schema = db.schemas[tableName]
					if (schema == nil) then
						return error (string.format ("Unexpected table row at line %d: there was no schema for table \"%s\" before", lineNumber, tableName), 0)
					end

					-- print(DumpObject(rowData))

					if (# rowData ~= # schema) then
						return error (string.format ("Inconsistent tale row data at line %d: expected %d fields, read %d", lineNumber, # schema, # rowData), 0)
					end

					local reqFields = const.requiredFields[tableName]
					assert(reqFields ~= nil)

					local processedRow = { }

					for i,v in ipairs(rowData) do
						local fieldName = schema[i]
						assert (fieldName ~= nil)

						local required = false
						for _,n in ipairs(reqFields) do
							if (n == fieldName) then
								required = true
								break
							end
						end

						if (required == true and v ~= JSON.NULL) then
							processedRow[fieldName] = v
						end
					end

					if (processedRow.id == nil) then
						return error (string.format ("Invalid data row at line %d: missing 'id' field", lineNumber), 0)
					end

					-- print(DumpObject(processedRow))
					assert(db.tables[tableName] ~= nil)

					if (db.tables[tableName][processedRow.id] ~= nil) then
						return error (string.format ("Row with a duplicated id at line %d: \"%s\"", lineNumber, processedRow.id), 0)
					end

					db.tables[tableName][processedRow.id] = processedRow
				end
			end
		end
	until false

	-- print(DumpObject(db))
	return db
end

-- ---------------------------------------------------------------------
-- processData.
--
-- Processed parsed database (db) and returns processed data (pd).
-- It's used as additional hint data when converting database to Jelly.
-- ---------------------------------------------------------------------

function processData(db)
	if (db.tables.users == nil) then
		return error (string.format ("Dump file missing required 'users' table"), 0)
	end

	if (db.tables.spaces == nil) then
		return error (string.format ("Dump file missing required 'spaces' table"), 0)
	end

	local pd = { } -- "Processed data"

	pd.usedUsers = { }

	-- iterate tables and put used users to list.
	assert(db.tables.spaces ~= nil)
	for k,v in pairs(db.tables.spaces) do
		if (v.payer_id ~= nil) then
			pd.usedUsers[v.payer_id] = true
		end
	end

	assert(db.tables.milestones ~= nil)
	for k,v in pairs(db.tables.milestones) do
		if (v.user_id ~= nil) then
			pd.usedUsers[v.user_id] = true
		end

		if (v.created_by ~= nil) then
			pd.usedUsers[v.created_by] = true
		end

		if (v.updated_by ~= nil) then
			pd.usedUsers[v.updated_by] = true
		end
	end

	assert(db.tables.tickets ~= nil)
	for k,v in pairs(db.tables.tickets) do
		if (v.reporter_id ~= nil) then
			pd.usedUsers[v.reporter_id] = true
		end

		if (v.assigned_to_id ~= nil) then
			pd.usedUsers[v.assigned_to_id] = true
		end
	end

	assert(db.tables.ticket_comments ~= nil)
	for k,v in pairs(db.tables.ticket_comments) do
		if (v.user_id ~= nil) then
			pd.usedUsers[v.user_id] = true
		end
	end

	return pd
end

-- ---------------------------------------------------------------------
-- convertData.
--
-- Converts parsed database (db) and processed data (pd) into Jelly.
-- Returns XML tree that needs to be written.
-- ---------------------------------------------------------------------

function convertData(db, pd)
	assert(db ~= nil)
	assert(pd ~= nil)

	local xmlRoot = xmlCreateTag("JiraJelly")
	xmlSetAttr(xmlRoot, "xmlns:jira", "jelly:com.atlassian.jira.jelly.enterprise.JiraTagLib")
	xmlSetAttr(xmlRoot, "xmlns:core", "jelly:core")

	-- Request Component Manager class instance, it will be used later for custom fields.
	--	<core:invokeStatic className="com.atlassian.jira.ComponentManager" method="getInstance" var="componentManager"/>
	do
		local xmlCoreInvokeStatic = xmlCreateTag("core:invokeStatic")

		xmlSetAttr(xmlCoreInvokeStatic, "className", "com.atlassian.jira.ComponentManager")
		xmlSetAttr(xmlCoreInvokeStatic, "method", "getInstance")
		xmlSetAttr(xmlCoreInvokeStatic, "var", "componentManager")

		xmlAppendTag (xmlRoot, xmlCoreInvokeStatic)
	end

	-- Request Custom Field Manager object, it will be used later for custom fields.
	--	<core:invoke on="${componentManager}" method="getCustomFieldManager" var="customFieldManager"/>
	do
		local xmlCoreInvoke = xmlCreateTag("core:invoke")

		xmlSetAttr(xmlCoreInvoke, "on", "${componentManager}")
		xmlSetAttr(xmlCoreInvoke, "method", "getCustomFieldManager")
		xmlSetAttr(xmlCoreInvoke, "var", "customFieldManager")

		xmlAppendTag (xmlRoot, xmlCoreInvoke)
	end

	-- Request Project Manager object, it will be used later for custom fields.
	--	<core:invoke on="${componentManager}" method="getProjectManager" var="projectManager"/>
	do
		local xmlCoreInvoke = xmlCreateTag("core:invoke")

		xmlSetAttr(xmlCoreInvoke, "on", "${componentManager}")
		xmlSetAttr(xmlCoreInvoke, "method", "getProjectManager")
		xmlSetAttr(xmlCoreInvoke, "var", "projectManager")

		xmlAppendTag (xmlRoot, xmlCoreInvoke)
	end

	-- Convert users (only those that are used and those needs to be created).
	local createdUsers = { }

	-- print(DumpObject(pd))

	assert(db.tables.users ~= nil)
	for userId,user in pairs(db.tables.users) do
		assert(user.login ~= nil)
		if (pd.usedUsers[userId] ~= nil) then

			local userMapping = getUserMapping(user.login)
			assert (userMapping ~= nil)

			if (userMapping.create == true and createdUsers[userMapping.username] == nil) then
				if (userMapping.email == nil) then
					return error (string.format ("Missing required field \"email\" in mapping for user login \"%s\" in settings file", user.login), 0)
				end

				if (userMapping.fullname == nil) then
					return error (string.format ("Missing required field \"fullname\" in mapping for user login \"%s\" in settings file", user.login), 0)
				end

				local jjCreateUser = xmlCreateTag("jira:CreateUser")
				assert(jjCreateUser ~= nil)

				xmlSetAttr (jjCreateUser, "username", jellyEscape(userMapping.username))
				if (userMapping.send_email == true) then
					xmlSetAttr (jjCreateUser, "sendEmail", "true")
				else
					xmlSetAttr (jjCreateUser, "sendEmail", "false")
				end
				xmlSetAttr (jjCreateUser, "email", jellyEscape(userMapping.email))
				xmlSetAttr (jjCreateUser, "fullname", jellyEscape(userMapping.fullname))

				if (userMapping.password ~= nil) then
					xmlSetAttr (jjCreateUser, "password", jellyEscape(userMapping.password))
					xmlSetAttr (jjCreateUser, "confirm", jellyEscape(userMapping.password))
				end

				xmlAppendTag (xmlRoot, jjCreateUser)

				createdUsers[userMapping.username] = true
			end
		end
	end

	local writtenTickets = { }
	-- Convert projects.
	assert(db.tables.spaces ~= nil)
	for spaceId,space in pairs(db.tables.spaces) do
		local spaceMapping = getSettingsTable("spaces", space.name)
		if (spaceMapping == nil) then
			return error (string.format ("Missing mapping for space \"%s\"  (\"%s\") in settings file", spaceId, space.name), 0)
		end

		-- Create or skip space.
		if (spaceMapping.skip == true) then
			print (string.format ("Info: Skipping space \"%s\" (\"%s\")", spaceId, space.name))
		else
			local projectTag = nil

			-- Compute project key - get it from mapping, or generate from space wiki name.
			local projectKey = string.upper (string.sub ( spaceMapping.key or space.wiki_name, 1, 3 ) )
			assert(projectKey ~= nil)

			-- TODO: Add check that projectKey contains only alphanumeric chars.

			-- Decide, if we want create new space, or use existing.
			if (spaceMapping.create == true) then
				if (spaceMapping.key == nil) then
					return error (string.format ("Missing required field \"key\" in space mapping \"%s\" (\"%s\") in settings file", spaceId, space.name), 0)
				end

				assert(space.payer_id ~= nil)
				local payerUser = db.tables.users[space.payer_id]
				assert(payerUser ~= nil)

				local mappedUserName = mapUserName(payerUser.login)
				assert(mappedUserName ~= nil)

				local jjCreateProject = xmlCreateTag("jira:CreateProject")
				assert(jjCreateProject ~= nil)

				xmlSetAttr (jjCreateProject, "key", projectKey)
				xmlSetAttr (jjCreateProject, "name", jellyEscape(spaceMapping.name or space.name))
				xmlSetAttr (jjCreateProject, "description", jellyEscape(spaceMapping.description or space.description))
				xmlSetAttr (jjCreateProject, "lead", jellyEscape(mappedUserName))
				projectTag = jjCreateProject
			else
				--[[
				local jjLoadProject = xmlCreateTag("jira:LoadProject")
				assert(jjLoadProject ~= nil)
				xmlSetAttr (jjLoadProject, "project-name", spaceMapping.name or space.name)
				projectTag = jjLoadProject
				--]]
				projectTag = xmlRoot
			end

			-- Request Project object, it will be used later for custom fields.
			--	<core:invoke on="${projectManager}" method="getProjectObjByKey" var="XXX_project">
			--		<core:arg type="java.lang.String" value="JIT"/>
			--	</core:invoke>
			do
				local xmlCoreInvoke = xmlCreateTag("core:invoke")

				xmlSetAttr(xmlCoreInvoke, "on", "${projectManager}")
				xmlSetAttr(xmlCoreInvoke, "method", "getProjectObjByKey")
				xmlSetAttr(xmlCoreInvoke, "var", projectKey .. "_project")

				local xmlCoreArg_1 = xmlCreateTag("core:arg")

				xmlSetAttr(xmlCoreArg_1, "type", "java.lang.String")
				xmlSetAttr(xmlCoreArg_1, "value", projectKey  )

				xmlAppendTag (xmlCoreInvoke, xmlCoreArg_1)

				xmlAppendTag (projectTag, xmlCoreInvoke)
			end

			-- Request Project id, it will be used later for custom fields.
			--	<core:invoke on="${XXX_project}" method="getId" var="XXX_project_Id"/>
			do
				local xmlCoreInvoke = xmlCreateTag("core:invoke")

				xmlSetAttr(xmlCoreInvoke, "on", "${" .. projectKey .. "_project}")
				xmlSetAttr(xmlCoreInvoke, "method", "getId")
				xmlSetAttr(xmlCoreInvoke, "var", projectKey .. "_project_Id")

				xmlAppendTag (projectTag, xmlCoreInvoke)
			end

			-- Request 
			--	<core:new className="com.atlassian.jira.issue.context.ProjectContext" var="XXX_project_ctx">
			--		<core:arg type="java.lang.Long" value="${XXX_project_Id}"/>
			--	</core:new>
			do
				local xmlCoreNew = xmlCreateTag("core:new")

				xmlSetAttr(xmlCoreNew, "className", "com.atlassian.jira.issue.context.ProjectContext")
				xmlSetAttr(xmlCoreNew, "var", projectKey .. "_project_ctx")

				local xmlCoreArg_1 = xmlCreateTag("core:arg")

				xmlSetAttr(xmlCoreArg_1, "type", "java.lang.Long")
				xmlSetAttr(xmlCoreArg_1, "value", "${" .. projectKey .. "_project_Id}")

				xmlAppendTag (xmlCoreNew, xmlCoreArg_1)

				xmlAppendTag (projectTag, xmlCoreNew)
			end

			-- Iterate Space tools, looking for 'TicketTool', it stores components in its settings.
			local spaceComponents = { }
			local ticketToolId = nil

			assert(db.tables.space_tools ~= nil)
			for spaceToolId,spaceTool in pairs(db.tables.space_tools) do
				if (spaceTool.space_id == spaceId and spaceTool.type == "TicketTool") then
					ticketToolId = spaceToolId

					--assert(spaceTool.settings ~= nil)
					--local settingsParsed = yaml.load(spaceTool.settings)
					--if (settingsParsed == nil) then
					--	return error (string.format ("Failed to parse TicketTool tool settings for space \"%s\" (\"%s\")", spaceId, space.name), 0)
					--end

					-- print(DumpObject(settingsParsed))
					--local components = settingsParsed[":components"]
					--if (components ~= nil) then
					--	for componentIdx,component in pairs(components) do
					--		if (type(componentIdx) == "number") then
					--			assert(type(component) == "string")
					--			spaceComponents[componentIdx] = component
					--		end
					--	end
					--end

					break -- We do not want to continue after tool is found.
				end
			end

			-- print(DumpObject(spaceComponents))

			-- Add components to project.
			for componentIdx,component in pairs(spaceComponents) do
				local jjAddComponent = xmlCreateTag("jira:AddComponent")
				assert(jjAddComponent ~= nil)
				
				xmlSetAttr (jjAddComponent, "project-key", projectKey)
				xmlSetAttr (jjAddComponent, "name", jellyEscape(component))
				xmlSetAttr (jjAddComponent, "description", jellyEscape(component))

				xmlAppendTag (projectTag, jjAddComponent)
			end

			-- Create custom field for storing old Assembla issue ID (for reference). Optional, only if set in settings.
			local tickedidFieldSettings = spaceMapping.ticketid_field
			local oldIssueIdFieldId = nil
			if (tickedidFieldSettings ~= nil) then
				local jjCreateCustomField_OldIssueId = xmlCreateTag("jira:CreateCustomField")
				assert(jjCreateCustomField_OldIssueId ~= nil)

				local oldIssueIdFieldName = tickedidFieldSettings.name or "Assembla Ticket ID"
				oldIssueIdFieldId = projectKey .. "_customFieldId_ticketid"

				xmlSetAttr (jjCreateCustomField_OldIssueId, "fieldType", "readonlyfield")
				xmlSetAttr (jjCreateCustomField_OldIssueId, "fieldScope", "project")
				xmlSetAttr (jjCreateCustomField_OldIssueId, "fieldName", jellyEscape(oldIssueIdFieldName))
				xmlSetAttr (jjCreateCustomField_OldIssueId, "projectKey", projectKey)
				xmlSetAttr (jjCreateCustomField_OldIssueId, "description", jellyEscape(tickedidFieldSettings.description or "Old ticket ID (from Assembla)"))
				xmlSetAttr (jjCreateCustomField_OldIssueId, "searcher", "textsearcher")
				xmlSetAttr (jjCreateCustomField_OldIssueId, "customFieldIdVar", oldIssueIdFieldId )

				xmlAppendTag (projectTag, jjCreateCustomField_OldIssueId) -- Append it to project.

				-- Add it to screen, if needed.
				if (tickedidFieldSettings.screen_name ~= nil) then
					local jjAddFieldToScreen = xmlCreateTag("jira:AddFieldToScreen")
					assert(jjAddFieldToScreen ~= nil)

					xmlSetAttr (jjAddFieldToScreen, "fieldId", "${" .. oldIssueIdFieldId .. ".getId()}")
					xmlSetAttr (jjAddFieldToScreen, "screen", jellyEscape(tickedidFieldSettings.screen_name))
					if (tickedidFieldSettings.screen_tab ~= nil) then
						xmlSetAttr (jjAddFieldToScreen, "tab", jellyEscape(tickedidFieldSettings.screen_tab))
					end

					xmlAppendTag (projectTag, jjAddFieldToScreen) -- Append it to project.
				end
			end

			-- Create custom field for storing old Assembla status (for reference). Optional, only if set in settings.
			local statusFieldSettings = spaceMapping.status_field
			local statusFieldId = nil
			local statusFieldValues = nil

			if (statusFieldSettings ~= nil) then
				local statusNames = nil

				assert(db.tables.ticket_statuses ~= nil)
				for statusId,status in pairs(db.tables.ticket_statuses) do
					if (status.space_tool_id == ticketToolId) then
						if (statusNames == nil) then
							statusNames = { }
						end

						local v = { }
						v.order = status.list_order
						v.name = status.name

						table.insert (statusNames, v)
					end
				end

				if (statusNames ~= nil) then
					statusFieldValues = { }

					local statusFieldName = statusFieldSettings.name or "Status"
					statusFieldId = projectKey .. "_customField_status"

					-- Sort table according to order.
					table.sort (statusNames, function(a, b) return a.order < b.order end)

					local jjCreateCustomField_Status = xmlCreateTag("jira:CreateCustomField")
					assert(jjCreateCustomField_Status ~= nil)

					xmlSetAttr (jjCreateCustomField_Status, "fieldType", "select")
					xmlSetAttr (jjCreateCustomField_Status, "fieldScope", "project")
					xmlSetAttr (jjCreateCustomField_Status, "fieldName", jellyEscape(statusFieldName))
					xmlSetAttr (jjCreateCustomField_Status, "projectKey", projectKey)
					xmlSetAttr (jjCreateCustomField_Status, "description", jellyEscape(statusFieldSettings.description or "Old status (from Assembla)"))
					xmlSetAttr (jjCreateCustomField_Status, "searcher", "multiselectsearcher")
					xmlSetAttr (jjCreateCustomField_Status, "customFieldIdVar", statusFieldId )

					for i,status in ipairs(statusNames) do
						local jjAddCustomFieldSelectValue = xmlCreateTag("jira:AddCustomFieldSelectValue")
						assert(jjAddCustomFieldSelectValue ~= nil)

						xmlSetAttr (jjAddCustomFieldSelectValue, "value", jellyEscape(status.name))

						xmlAppendTag (jjCreateCustomField_Status, jjAddCustomFieldSelectValue)

						statusFieldValues[status.name] = i
					end

					xmlAppendTag (projectTag, jjCreateCustomField_Status)

					-- Add it to screen, if needed.
					if (statusFieldSettings.screen_name ~= nil) then
						local jjAddFieldToScreen = xmlCreateTag("jira:AddFieldToScreen")
						assert(jjAddFieldToScreen ~= nil)

						xmlSetAttr (jjAddFieldToScreen, "fieldId", "${" .. statusFieldId .. ".getId()}")
						xmlSetAttr (jjAddFieldToScreen, "screen", jellyEscape(statusFieldSettings.screen_name))
						if (statusFieldSettings.screen_tab ~= nil) then
							xmlSetAttr (jjAddFieldToScreen, "tab", jellyEscape(statusFieldSettings.screen_tab))
						end

						xmlAppendTag (projectTag, jjAddFieldToScreen) -- Append it to project.
					end

					-- Get options for this field. Used for mapping value IDs.
					-- <core:invoke on="${XXX_customFieldId_status}" method="getOptions" var="XXX_customFieldId_status_options">
					--		<core:arg type="java.lang.String" value=""/>
					--		<core:arg type="com.atlassian.jira.issue.context.ProjectContext" value="${XXX_project_ctx}"/>
					--	</core:invoke>
					do
						local xmlCoreInvoke = xmlCreateTag("core:invoke")

						xmlSetAttr(xmlCoreInvoke, "on", "${" .. statusFieldId .. "}")
						xmlSetAttr(xmlCoreInvoke, "method", "getOptions")
						xmlSetAttr(xmlCoreInvoke, "var", statusFieldId .. "_options")

						local xmlCoreArg_1 = xmlCreateTag("core:arg")

						xmlSetAttr(xmlCoreArg_1, "type", "java.lang.String")
						xmlSetAttr(xmlCoreArg_1, "value", "")

						xmlAppendTag (xmlCoreInvoke, xmlCoreArg_1)

						local xmlCoreArg_2 = xmlCreateTag("core:arg")

						xmlSetAttr(xmlCoreArg_2, "type", "com.atlassian.jira.issue.context.ProjectContext")
						xmlSetAttr(xmlCoreArg_2, "value", "${" .. projectKey .. "_project_ctx}")

						xmlAppendTag (xmlCoreInvoke, xmlCoreArg_2)

						xmlAppendTag (projectTag, xmlCoreInvoke)
					end

					-- Iterate statusFieldValues and request Jira value IDs.
					for statusName,statusIdx in pairs(statusFieldValues) do
						--	<core:invoke on="${XXX_customFieldId_status_options}" method="getOptionForValue" var="XXX_customFieldId_status_options_Y">
						--		<core:arg type="java.lang.String" value="<text value>"/>
						--		<core:arg type="java.lang.Long" />
						--	</core:invoke>
						do
							local xmlCoreInvoke = xmlCreateTag("core:invoke")

							xmlSetAttr(xmlCoreInvoke, "on", "${" .. statusFieldId .. "_options}")
							xmlSetAttr(xmlCoreInvoke, "method", "getOptionForValue")
							xmlSetAttr(xmlCoreInvoke, "var", statusFieldId .. "_options_" .. tostring(statusIdx))

							local xmlCoreArg_1 = xmlCreateTag("core:arg")

							xmlSetAttr(xmlCoreArg_1, "type", "java.lang.String")
							xmlSetAttr(xmlCoreArg_1, "value", jellyEscape(statusName))

							xmlAppendTag (xmlCoreInvoke, xmlCoreArg_1)

							local xmlCoreArg_2 = xmlCreateTag("core:arg")

							xmlSetAttr(xmlCoreArg_2, "type", "java.lang.Long")
							-- No value, Java null used.

							xmlAppendTag (xmlCoreInvoke, xmlCoreArg_2)

							xmlAppendTag (projectTag, xmlCoreInvoke)
						end

						--	<core:invoke on="${XXX_customFieldId_status_options_Y}" method="getOptionId" var="customFieldId_status_options_Y_id" />
						do
							local xmlCoreInvoke = xmlCreateTag("core:invoke")

							xmlSetAttr(xmlCoreInvoke, "on", "${" .. statusFieldId .. "_options_" .. tostring(statusIdx) .. "}")
							xmlSetAttr(xmlCoreInvoke, "method", "getOptionId")
							xmlSetAttr(xmlCoreInvoke, "var", statusFieldId .. "_options_" .. tostring(statusIdx) .. "_id")

							xmlAppendTag (projectTag, xmlCoreInvoke)
						end
					end
				end
			end

			-- Create custom field (or use GreenHopper sprints, not supported yet) for milestones. Optional.
			local milestoneFieldSettings = spaceMapping.milestone_field
			local milestoneFieldId = nil
			local milestoneFieldValues = nil

			if (milestoneFieldSettings ~= nil) then
				local milestonesTitles = nil

				assert(db.tables.milestones ~= nil)
				for milestoneId,milestone in pairs(db.tables.milestones) do
					if (milestone.space_id == spaceId) then
						if (milestonesTitles == nil) then
							milestonesTitles = { }
						end

						table.insert (milestonesTitles, milestone.title)
					end
				end

				if (milestonesTitles ~= nil) then
					milestoneFieldValues = { }

					local milestoneFieldName = milestoneFieldSettings.name or "Milestone"
					milestoneFieldId = projectKey .. "_customField_milestone"

					-- Sort table alphabetically.
					table.sort (milestonesTitles)

					local jjCreateCustomField_Milestone = xmlCreateTag("jira:CreateCustomField")
					assert(jjCreateCustomField_Milestone ~= nil)

					xmlSetAttr (jjCreateCustomField_Milestone, "fieldType", "select")
					xmlSetAttr (jjCreateCustomField_Milestone, "fieldScope", "project")
					xmlSetAttr (jjCreateCustomField_Milestone, "fieldName", jellyEscape(milestoneFieldName))
					xmlSetAttr (jjCreateCustomField_Milestone, "projectKey", projectKey)
					xmlSetAttr (jjCreateCustomField_Milestone, "description", jellyEscape(milestoneFieldSettings.description or "Milestone"))
					xmlSetAttr (jjCreateCustomField_Milestone, "searcher", "multiselectsearcher")
					xmlSetAttr (jjCreateCustomField_Milestone, "customFieldIdVar", milestoneFieldId )

					for i,title in ipairs(milestonesTitles) do
						local jjAddCustomFieldSelectValue = xmlCreateTag("jira:AddCustomFieldSelectValue")
						assert(jjAddCustomFieldSelectValue ~= nil)

						xmlSetAttr (jjAddCustomFieldSelectValue, "value", jellyEscape(title))

						xmlAppendTag (jjCreateCustomField_Milestone, jjAddCustomFieldSelectValue)

						milestoneFieldValues[title] = i
					end

					xmlAppendTag (projectTag, jjCreateCustomField_Milestone)

					-- Add it to screen, if needed.
					if (milestoneFieldSettings.screen_name ~= nil) then
						local jjAddFieldToScreen = xmlCreateTag("jira:AddFieldToScreen")
						assert(jjAddFieldToScreen ~= nil)

						xmlSetAttr (jjAddFieldToScreen, "fieldId", "${" .. milestoneFieldId .. ".getId()}")
						xmlSetAttr (jjAddFieldToScreen, "screen", jellyEscape(milestoneFieldSettings.screen_name))
						if (tickedidFieldSettings.screen_tab ~= nil) then
							xmlSetAttr (jjAddFieldToScreen, "tab", jellyEscape(milestoneFieldSettings.screen_tab))
						end

						xmlAppendTag (projectTag, jjAddFieldToScreen) -- Append it to project.
					end

					-- Get options for this field. Used for mapping value IDs.
					-- <core:invoke on="${XXX_customFieldId_milestone}" method="getOptions" var="XXX_customFieldId_milestone_options">
					--		<core:arg type="java.lang.String" value=""/>
					--		<core:arg type="com.atlassian.jira.issue.context.ProjectContext" value="${XXX_project_ctx}"/>
					--	</core:invoke>
					do
						local xmlCoreInvoke = xmlCreateTag("core:invoke")

						xmlSetAttr(xmlCoreInvoke, "on", "${" .. milestoneFieldId .. "}")
						xmlSetAttr(xmlCoreInvoke, "method", "getOptions")
						xmlSetAttr(xmlCoreInvoke, "var", milestoneFieldId .. "_options")

						local xmlCoreArg_1 = xmlCreateTag("core:arg")

						xmlSetAttr(xmlCoreArg_1, "type", "java.lang.String")
						xmlSetAttr(xmlCoreArg_1, "value", "")

						xmlAppendTag (xmlCoreInvoke, xmlCoreArg_1)

						local xmlCoreArg_2 = xmlCreateTag("core:arg")

						xmlSetAttr(xmlCoreArg_2, "type", "com.atlassian.jira.issue.context.ProjectContext")
						xmlSetAttr(xmlCoreArg_2, "value", "${" .. projectKey .. "_project_ctx}")

						xmlAppendTag (xmlCoreInvoke, xmlCoreArg_2)

						xmlAppendTag (projectTag, xmlCoreInvoke)
					end

					-- Iterate statusFieldValues and request Jira value IDs.
					for milestoneName,milestoneIdx in pairs(milestoneFieldValues) do
						--	<core:invoke on="${XXX_customFieldId_milestone_options}" method="getOptionForValue" var="XXX_customFieldId_milestone_options_Y">
						--		<core:arg type="java.lang.String" value="<text value>"/>
						--		<core:arg type="java.lang.Long" />
						--	</core:invoke>
						do
							local xmlCoreInvoke = xmlCreateTag("core:invoke")

							xmlSetAttr(xmlCoreInvoke, "on", "${" .. milestoneFieldId .. "_options}")
							xmlSetAttr(xmlCoreInvoke, "method", "getOptionForValue")
							xmlSetAttr(xmlCoreInvoke, "var", milestoneFieldId .. "_options_" .. tostring(milestoneIdx))

							local xmlCoreArg_1 = xmlCreateTag("core:arg")

							xmlSetAttr(xmlCoreArg_1, "type", "java.lang.String")
							xmlSetAttr(xmlCoreArg_1, "value", jellyEscape(milestoneName))

							xmlAppendTag (xmlCoreInvoke, xmlCoreArg_1)

							local xmlCoreArg_2 = xmlCreateTag("core:arg")

							xmlSetAttr(xmlCoreArg_2, "type", "java.lang.Long")
							-- No value, Java null used.

							xmlAppendTag (xmlCoreInvoke, xmlCoreArg_2)

							xmlAppendTag (projectTag, xmlCoreInvoke)
						end

						--	<core:invoke on="${XXX_customFieldId_milestone_options_Y}" method="getOptionId" var="customFieldId_milestone_options_Y_id" />
						do
							local xmlCoreInvoke = xmlCreateTag("core:invoke")

							xmlSetAttr(xmlCoreInvoke, "on", "${" .. milestoneFieldId .. "_options_" .. tostring(milestoneIdx) .. "}")
							xmlSetAttr(xmlCoreInvoke, "method", "getOptionId")
							xmlSetAttr(xmlCoreInvoke, "var", milestoneFieldId .. "_options_" .. tostring(milestoneIdx) .. "_id")

							xmlAppendTag (projectTag, xmlCoreInvoke)
						end
					end
				end
			end

			-- Iterate "workflow property defs" looking for custom fields, then look at settings for mapping.
			local versionsMap = { }
			local fixedVersionsMap = { }
			local mappedFields = { }
			local versionsList = nil

			if (ticketToolId ~= nil) then
				assert(db.tables.workflow_property_defs ~= nil)
				for workflowPropertyDefId,workflowPropertyDef in pairs(db.tables.workflow_property_defs) do
					-- print(DumpObject(workflowPropertyDef))

					if (workflowPropertyDef.space_tool_id == ticketToolId) then
						local propertyDefMapping = getSettingsTable("workflow_property_defs", workflowPropertyDefId)

						-- print(DumpObject(propertyDefMapping))

						local mapped = false

						if (propertyDefMapping ~= nil) then
							-- Check, if this is special mapping of field to 'versions' JIRA entity.
							if (propertyDefMapping.is_versions == true) then
								if (workflowPropertyDef.type ~= "WorkflowText") then
									return error (string.format ("Type of custom field \"%s\" (\"%s\") in space \"%s\" (\"%s\") used as version field must be \"WorkflowText\""
										,workflowPropertyDefId, workflowPropertyDef.title, spaceId, space.name), 0)
								end

								if (versionsList == nil) then
									versionsList = { }
								end

								-- Iterate "workflow_property_vals" looking for values for versions. Store only unique.

								assert(db.tables.workflow_property_vals ~= nil)
								for workflowPropertyValId,workflowPropertyVal in pairs(db.tables.workflow_property_vals) do
									if (workflowPropertyVal.workflow_property_def_id == workflowPropertyDefId and
										workflowPropertyVal.space_tool_id == ticketToolId)
									then
										versionsList[workflowPropertyVal.value] = true -- Currently it's just a marker.

										-- This will be used later, when writing issues.
										versionsMap[workflowPropertyVal.workflow_instance_id] = workflowPropertyVal.value
									end
								end

								mappedFields[workflowPropertyDefId] = propertyDefMapping
								mapped = true
							-- Check, if this is special mapping of field to 'fixed in versions' JIRA entity.
							elseif (propertyDefMapping.is_fixed_versions == true) then
								if (workflowPropertyDef.type ~= "WorkflowText") then
									return error (string.format ("Type of custom field \"%s\" (\"%s\") in space \"%s\" (\"%s\") used as fixed version field must be \"WorkflowText\""
										,workflowPropertyDefId, workflowPropertyDef.title, spaceId, space.name), 0)
								end

								if (versionsList == nil) then
									versionsList = { }
								end

								assert(db.tables.workflow_property_vals ~= nil)
								for workflowPropertyValId,workflowPropertyVal in pairs(db.tables.workflow_property_vals) do
									if (workflowPropertyVal.workflow_property_def_id == workflowPropertyDefId and
										workflowPropertyVal.space_tool_id == ticketToolId)
									then
										versionsList[workflowPropertyVal.value] = true -- Currently it's just a marker.

										-- This will be used later, when writing issues.
										fixedVersionsMap[workflowPropertyVal.workflow_instance_id] = workflowPropertyVal.value
									end
								end

								mappedFields[workflowPropertyDefId] = propertyDefMapping
								mapped = true
							end
						end

						if (mapped == false) then
							-- Unmapped field.
							print (string.format ("Warning: field \"%s\" (\"%s\") in space \"%s\" (\"%s\") unmapped, this is not supported yet."
								, workflowPropertyDefId, workflowPropertyDef.title, spaceId, space.name))
						end
					end
				end
			end

			-- Iterate versions list and create them.
			if (versionsList ~= nil) then
				-- print(DumpObject(versionsList))
				for version in pairs(versionsList) do
					local jjAddVersion = xmlCreateTag("jira:AddVersion")
					assert(jjAddVersion ~= nil)
				
					xmlSetAttr (jjAddVersion, "project-key", projectKey)
					xmlSetAttr (jjAddVersion, "name", jellyEscape(version))

					xmlAppendTag (projectTag, jjAddVersion)
				end
			end

			-- Iterate tickets, creating them.
			assert(db.tables.tickets ~= nil)
			for ticketId,ticket in pairs(db.tables.tickets) do
				if (ticket.space_id == spaceId) then
					local jjCreateIssue = xmlCreateTag("jira:CreateIssue")
					assert(jjCreateIssue ~= nil)

					xmlSetAttr (jjCreateIssue, "project-key", projectKey)
					-- xmlSetAttr (jjAddVersion, "issueType", "Bug")
					xmlSetAttr (jjCreateIssue, "summary", jellyEscape(ticket.summary))

					local mappedPriority = getSettingsTable("priorities", ticket.priority)
					if (mappedPriority ~= nil and mappedPriority.name ~= nil) then
						xmlSetAttr (jjCreateIssue, "priority", jellyEscape(mappedPriority.name))
					else
						print (string.format ("Warning: priority \"%s\" unmapped, using default priority.", ticket.priority))
					end

					-- Write component field, if found. Optional.
					if (ticket.component_id ~= nil) then
						local compId = spaceComponents[tonumber(ticket.component_id)]
						if (compId ~= nil) then
							xmlSetAttr (jjCreateIssue, "components", jellyEscape(compId))
						end
					end

					-- Write versions field, if present. Optional.
					local versions = versionsMap[ticketId]
					if 	(versions ~= nil) then
						xmlSetAttr (jjCreateIssue, "versions", jellyEscape(versions))
					end

					-- Write fixed versions field, if present. Optional.
					local fixedVersions = fixedVersionsMap[ticketId]
					if 	(fixedVersions ~= nil) then
						xmlSetAttr (jjCreateIssue, "fixVersions", jellyEscape(fixedVersions))
					end

					-- Map and write reporter. Mandatory! Use convert_user or space owner if user not found.
					-- print(ticket.number)
					local reporterUser = db.tables.users[ticket.reporter_id] or spaceMapping.convert_user or db.tables.users[space.payer_id]
					assert(reporterUser ~= nil)
					local reporterUserName = mapUserName(reporterUser.login)
					assert(reporterUserName ~= nil)

					xmlSetAttr (jjCreateIssue, "reporter", jellyEscape(reporterUserName))

					-- Map and write assignee. It's optional. Use automatic assignment, if not found (was removed from team).
					local status = db.tables.ticket_statuses[ticket.ticket_status_id]
					assert (status ~= nil)

					local statusMapping = getSettingsTable("statuses", status.name )

					if (statusMapping ~= nil and statusMapping.workflow_action ~= nil) then
						local assigneeUser = spaceMapping.convert_user or db.tables.users[space.payer_id]
						assert(assigneeUser ~= nil)
						local assigneeUserName = mapUserName(assigneeUser.login)
						assert(assigneeUserName ~= nil)

						xmlSetAttr (jjCreateIssue, "assignee", jellyEscape(assigneeUserName))
					else
						if (ticket.assigned_to_id ~= nil and db.tables.users[ticket.assigned_to_id] ~= nil) then
							local assigneeUser = db.tables.users[ticket.assigned_to_id]
							assert(assigneeUser ~= nil)
							local assigneeUserName = mapUserName(assigneeUser.login)
							assert(assigneeUserName ~= nil)

							xmlSetAttr (jjCreateIssue, "assignee", jellyEscape(assigneeUserName))
						else
							xmlSetAttr (jjCreateIssue, "assignee", "-1")
						end
					end
					
					-- Description. Optional.
					if (ticket.description ~= nil) then
						xmlSetAttr (jjCreateIssue, "description", jellyEscape(ticket.description))
					end

					-- Creation date. Mandatory.
					assert(ticket.created_on ~= nil)
					-- fix date format
					ticket.created_on=ticket.created_on:gsub("%T", " ")
					ticket.created_on=ticket.created_on:gsub("%+.*", "")
					xmlSetAttr (jjCreateIssue, "created", jellyEscape(ticket.created_on))

					-- Update date. Mandatory.
					assert(ticket.updated_at ~= nil)
					--fix date format
					ticket.updated_at=ticket.updated_at:gsub("%T", " ")
					ticket.updated_at=ticket.updated_at:gsub("%+.*", "")
					xmlSetAttr (jjCreateIssue, "updated", jellyEscape(ticket.updated_at))

					xmlSetAttr (jjCreateIssue, "duplicateSummary", "ignore")

					xmlSetAttr (jjCreateIssue, "issueIdVar", "issueId_" .. ticketId)
					xmlSetAttr (jjCreateIssue, "issueKeyVar", "issueKey_" .. ticketId)

					-- Add custom field for original issue id. Optional, only if this field was created.
					if (oldIssueIdFieldId ~= nil) then
						local jjAddCustomFieldValue_OriginalID = xmlCreateTag("jira:AddCustomFieldValue")
						assert(jjAddCustomFieldValue_OriginalID ~= nil)

						xmlSetAttr (jjAddCustomFieldValue_OriginalID, "id", "${" .. oldIssueIdFieldId .. ".getId()}" )
						xmlSetAttr (jjAddCustomFieldValue_OriginalID, "value", jellyEscape(tostring(ticket.number)) )

						xmlAppendTag (jjCreateIssue, jjAddCustomFieldValue_OriginalID)
					end

					-- Add custom field for Assembla status. Optional, only if this field was created.
					if (statusFieldId ~= nil and ticket.ticket_status_id ~= nil and statusFieldValues ~= nil) then
						local status = db.tables.ticket_statuses[ticket.ticket_status_id]
						assert(status ~= nil)

						-- print(DumpObject(statusFieldValues))
						local valueIdx = statusFieldValues[status.name]
						assert(valueIdx ~= nil)

						local jjAddCustomFieldValue_Status = xmlCreateTag("jira:AddCustomFieldValue")
						assert(jjAddCustomFieldValue_Status ~= nil)

						xmlSetAttr (jjAddCustomFieldValue_Status, "id", "${" .. statusFieldId .. ".getId()}" )
						xmlSetAttr (jjAddCustomFieldValue_Status, "value", "${" .. statusFieldId .. "_options_" .. tostring(valueIdx) .. "_id}"  )

						xmlAppendTag (jjCreateIssue, jjAddCustomFieldValue_Status)
					end

					-- Add custom field for Assembla milestone. Optional, only if this field was created.
					if (milestoneFieldId ~= nil and ticket.milestone_id ~= nil and milestoneFieldValues ~= nil) then
						local milestone = db.tables.milestones[ticket.milestone_id]
						assert(milestone ~= nil)

						local valueIdx = milestoneFieldValues[milestone.title]
						assert(valueIdx ~= nil)

						local jjAddCustomFieldValue_Milestone = xmlCreateTag("jira:AddCustomFieldValue")
						assert(jjAddCustomFieldValue_Milestone ~= nil)

						xmlSetAttr (jjAddCustomFieldValue_Milestone, "id", "${" .. milestoneFieldId .. ".getId()}" )
						xmlSetAttr (jjAddCustomFieldValue_Milestone, "value", "${" .. milestoneFieldId .. "_options_" .. tostring(valueIdx) .. "_id}" )

						xmlAppendTag (jjCreateIssue, jjAddCustomFieldValue_Milestone)
					end

					writtenTickets[ticketId] = ticket -- used later for linking tickets.

					xmlAppendTag (projectTag, jjCreateIssue)

					-- Iterate ticket comments, searching for those belonging to currently created ticket.
					assert(db.tables.ticket_comments ~= nil)
					for commentId,comment in pairs(db.tables.ticket_comments) do
						if (comment.ticket_id == ticketId and comment.comment ~= nil and string.len(comment.comment) > 0) then
							local jjAddComment = xmlCreateTag("jira:AddComment")
							assert(jjAddComment ~= nil)

							-- Map comment user. Mandatory! Use payer_id if user not found (was removed from team).
							local commentUser = db.tables.users[comment.user_id] or spaceMapping.convert_user or db.tables.users[space.payer_id]
							assert(commentUser ~= nil)
							local commentUserName = mapUserName(commentUser.login)
							assert(commentUserName ~= nil)

							local fullComment = nil
							-- Parse and process changes. Then append them to comment text at the end.
							if (comment.ticket_changes ~= nil and not (spaceMapping.convert_ticket_changes == false)) then
								local changesParsed = yaml.load(comment.ticket_changes)
								if (changesParsed ~= nil) then
									-- print(DumpObject(changesParsed))
									if (# changesParsed > 0) then
										local changesStr = "{quote}Changes:\n"

										for i,change in ipairs(changesParsed) do
											assert (# change == 3) -- Must be 3 fields: id, old, new.
											local changesMap = getSettingsTable("commentChanges", change[1])
											local fieldName
											if (changesMap ~= nil and changesMap.name ~= nil) then
												fieldName = changesMap.name
											elseif (const.commentChanges[change[1]] ~= nil and const.commentChanges[change[1]].name ~= nil) then
												fieldName = const.commentChanges[change[1]].name
											else
												fieldName = change[1]
											end
											
											local oldValue = string.len (change[2]) > 0 and change[2] or "<none>"
											local newValue = string.len (change[3]) > 0 and change[3] or "<none>"

											changesStr = changesStr .. string.format("|%s:|%s|%s|\n", fieldName, oldValue, newValue)
										end

										fullComment = changesStr .. "{quote}\n" .. comment.comment
									end
								else
									print (string.format ("Warning: Failed to parse ticket changes field for comment \"%s\" (ticket: \"%s\" (\"%s\") ), skipping it"
										, commentId, ticketId, ticket.number), 0)
								end
							end

							xmlSetAttr (jjAddComment, "issue-key", "${issueKey_" .. ticketId .. "}" )
							xmlSetAttr (jjAddComment, "commenter", jellyEscape(commentUserName) )
							xmlSetAttr (jjAddComment, "comment", jellyEscape(fullComment or comment.comment) )
							--fix date format
							comment.created_on=comment.created_on:gsub("%T", " ")
							comment.created_on=comment.created_on:gsub("%+.*", "")
							xmlSetAttr (jjAddComment, "created", jellyEscape(comment.created_on) )
							--fix date format
							comment.updated_at=comment.updated_at:gsub("%T", " ")
							comment.updated_at=comment.updated_at:gsub("%+.*", "")	

							--to avoid problem in import generated by Assembla which sometimes put time that's most recent that the create_on time
							--we choose the most recent time
							if comment.updated_at > comment.created_on then
								xmlSetAttr (jjAddComment, "updated", jellyEscape(comment.updated_at) )
							else
								xmlSetAttr (jjAddComment, "updated", jellyEscape(comment.created_on) )
							end
							xmlSetAttr (jjAddComment, "editedBy", jellyEscape(commentUserName) )

							xmlAppendTag (projectTag, jjAddComment)
						end
					end

				end
			end

			-- Finally store project in a root.
			xmlAppendTag (xmlRoot, projectTag)
		end
	end

	-- Iterate tickets associations, creating them.
	assert(db.tables.ticket_associations ~= nil)
	for ticketAssociationId,ticketAssociation in pairs(db.tables.ticket_associations) do
		if (writtenTickets[ticketAssociation.ticket1_id] ~= nil and writtenTickets[ticketAssociation.ticket2_id] ~= nil) then
			local linksMap = getSettingsTable("links", ticketAssociation.relationship )

			if (linksMap ~= nil and linksMap.type ~= nil) then
				local jjLinkIssue = xmlCreateTag("jira:LinkIssue")
				assert(jjLinkIssue ~= nil)

				xmlSetAttr (jjLinkIssue, "key", "${issueKey_" .. ticketAssociation.ticket1_id .. "}" )
				xmlSetAttr (jjLinkIssue, "linkKey", "${issueKey_" .. ticketAssociation.ticket2_id .. "}" )
				xmlSetAttr (jjLinkIssue, "linkDesc", jellyEscape(linksMap.type) )

				xmlAppendTag (xmlRoot, jjLinkIssue)
			end
		end
	end

	-- Iterate wriiten tickets list, issuing workflow changes, where needed.
	for ticketId,ticket in pairs(writtenTickets) do
		local status = db.tables.ticket_statuses[ticket.ticket_status_id]
		assert (status ~= nil)

		local statusMapping = getSettingsTable("statuses", status.name )

		if (statusMapping ~= nil and statusMapping.workflow_action ~= nil) then

			local jjTransitionWorkflow = xmlCreateTag("jira:TransitionWorkflow")
			assert(jjTransitionWorkflow ~= nil)

			xmlSetAttr (jjTransitionWorkflow, "key", "${issueKey_" .. ticketId .. "}" )
			xmlSetAttr (jjTransitionWorkflow, "workflowAction", jellyEscape(statusMapping.workflow_action) )
			if (statusMapping.resolution ~= nil) then
				xmlSetAttr (jjTransitionWorkflow, "resolution", jellyEscape(statusMapping.resolution) )
			end

			-- Map and write assignee. It's optional. Use automatic assignment if user not found (was removed from team).
			if (statusMapping.set_assignee == true) then
				if (ticket.assigned_to_id ~= nil and db.tables.users[ticket.assigned_to_id] ~= nil) then
					local assigneeUser = db.tables.users[ticket.assigned_to_id]
					assert(assigneeUser ~= nil)
					local assigneeUserName = mapUserName(assigneeUser.login)
					assert(assigneeUserName ~= nil)

					xmlSetAttr (jjTransitionWorkflow, "assignee", jellyEscape(assigneeUserName))
				else
					xmlSetAttr (jjTransitionWorkflow, "assignee", "-automatic-")
				end
			end

			xmlAppendTag (xmlRoot, jjTransitionWorkflow)
		end
	end

	return xmlRoot
end

-- =====================================================================
-- =====================================================================
--
-- Main.
--
-- =====================================================================
-- =====================================================================

-- ---------------------------------------------------------------------
-- process().
--
-- Main process func: parse dump file, process it, convert, write XML.
-- ---------------------------------------------------------------------

function process(inFileName, outFileName)

	local inFile,inFileErrorMsg = io.open (inFileName)

	if (inFile == nil) then
		return error (string.format ("Error opening dump file \"%s\": %s", inFileName, inFileErrorMsg), 0)
	end

	print (string.format ("> Parsing file \"%s\"...", inFileName))

	local db = parseFile(inFile)
	inFile:close()
	assert(db)

	print (string.format ("> Processing data..."))
	local pd = processData(db)
	assert(pd ~= nil)

	print (string.format ("> Converting data..."))
	local xml = convertData(db, pd)
	assert(xml)

	print (string.format ("> Writing data to file \"%s\"...", outFileName))
	local outFile,outFileErrorMsg = io.open (outFileName, "w")

	if (outFile == nil) then
		return error (string.format ("Error opening output file \"%s\": %s", outFileName, outFileErrorMsg), 0)
	end

	local res = xmlDump(outFile, xml)
	assert(res == true)

	outFile:close()

	return 0
end

-- ---------------------------------------------------------------------
-- Main chunk.
-- ---------------------------------------------------------------------

do
	-- dofile "DumpObject.lua"

	if (JSON == nil) then
		return error ("JSON.lua is missing", 0)
	end

	local settingsFile = "settings.lua";
	local dumpFile = nil;
	local outFile = nil;

	local argState = "opts";
	local argFailed = true;

	for i,arg in ipairs(arg) do
		if (argState == "opts") then
			if (arg == "-s") then
				argState = "settingsFile"
			else
				dumpFile = arg
				argState = "outFile"
			end
		elseif (argState == "settingsFile") then
			settingsFile = arg
			argState = "opts"
		elseif (argState == "dumpFile") then
			dumpFile = arg
			argState = "outFile"
		elseif (argState == "outFile") then
			outFile = arg
			argFailed = false
			argState = "unexpected"
		elseif (argState == "unexpected") then
			argFailed = true
			break
		end
	end

	dofile (settingsFile)

	if (settings == nil) then
		return error (string.format ("Settings file \"%s\" is missing required 'settings' table", settingsFile), 0)
	end

	if (argFailed == true or
		outFile == nil or
		dumpFile == nil)
	then
		io.write (string.format ("Usage: %s [-s <settings file>] <dump file> <output file>", arg[0]))
		return const.errorCodes.invalidArgs
	end

	return process(dumpFile, outFile)
end
