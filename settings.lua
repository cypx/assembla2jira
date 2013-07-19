-- =====================================================================
-- =====================================================================
--
-- Settings for assembla2jira .
--
-- This file must be in a valid LUA script format.
-- Read LUA Rederence Manual ( http://www.lua.org/manual/ )
-- if you're not familiar with LUA scripts.
-- 
-- Read assembla2jira Documentation at the project site
-- (http://code.google.com/p/assembla2jira/) for information on settings.
--
-- =====================================================================
-- =====================================================================

settings =
{
	["spaces"] =
	{
		["Test"] =
		{
			["create"] = true,
			["skip"] = false,
			["name"] = "JIRA Import Test",
			["key"] = "JIT",
			["description"] = "JIRA Import Test project",
			["convert_ticket_changes"] = true,
			["convert_user"] =
			{
				["login"] = "admin",
			},
			["ticketid_field"] =
			{
				["name"] = "Assembla Ticket ID",
				["description"] = "Old ticket ID (from Assembla)",
				["screen_name"] = "Default Screen",
				["screen_tab"] = "0",
			},
			["milestone_field"] =
			{
				["name"] = "Milestone",
				["description"] = "Milestone (from Assembla)",
				["screen_name"] = "Default Screen",
				["screen_tab"] = "0",
			},
			["status_field"] =
			{
				["name"] = "Status",
				["description"] = "Old status (from Assembla)",
				["screen_name"] = "Default Screen",
				["screen_tab"] = "0",
			},
		},

		["SkipSample"] =
		{
			["create"] = false,
			["skip"] = true,
			["name"] = "Skip This",
			["key"] = "SKP",
			["description"] = "This space will be skipped",
			["convert_ticket_changes"] = true,
		},
	},

	["workflow_property_defs"] =
	{
		["110703"] =
		{
			["is_versions"] = true,
		},

		["122343"] =
		{
			["is_fixed_versions"] = true,
		},
	},

	["statuses"] =
	{
		["New"] =
		{
		},

		["In Progress"] =
		{
			["workflow_action"] = "Start Progress",
			["resolution"] = "Work in progess",
			["set_assignee"] = true,
		},

		["Invalid"] =
		{
			["workflow_action"] = "Resolve Issue",
			["resolution"] = "Cannot Reproduce",
			["set_assignee"] = true,
		},

		["Fixed"] =
		{
			["workflow_action"] = "Close Issue",
			["resolution"] = "Fixed",
			["set_assignee"] = true,
		},

		["To test"] =
		{
			["resolution"] = "To test",
		},

		["Waiting information"] =
		{
			["workflow_action"] = "Start Progress",
			["set_assignee"] = false,
		},

		["To implement"] =
		{
			["workflow_action"] = "Start Progress",
			["set_assignee"] = false,
		},

		["Duplicate"] =
		{
			["workflow_action"] = "Close Issue",
			["resolution"] = "Duplicate",
			["set_assignee"] = true,
		},

		["Test pending"] =
		{
			["resolution"] = "To test",
			["set_assignee"] = false,
		},

		["Waiting subtask treatment"] =
		{
			["resolution"] = "Waiting subtask treatment",
			["set_assignee"] = false,
		},

	},

	["links"] =
	{
		-- 
		["0"] =
		{
			["type"] = "parent of",
		},

		["1"] =
		{
			["type"] = "child of",
		},

		["2"] =
		{
			["type"] = "relates to",
		},

		["3"] =
		{
			["type"] = "duplicates",
		},
	},

	["priorities"] =
	{
		["1"] =
		{
			["name"] = "Trivial",
		},

		["2"] =
		{
			["name"] = "Minor",
		},

		["3"] =
		{
			["name"] = "Major",
		},

		["4"] =
		{
			["name"] = "Critical",
		},

		["5"] =
		{
			["name"] = "Blocker",
		},
	},

	["users"] =
	{
		["admin"] =
		{
			["create"] = false,
			["username"] = "admin",
		},

		["SpaceOwner"] =
		{
			["create"] = false,
			["username"] = "admin",
		},

		["SomeAssemblaUser"] =
		{
			["create"] = true,
			["username"] = "jirauser1",
			["email"] = "jirauser1@example.com",
			["send_email"] = true,
			["fullname"] = "User 1",
		},

		["OtherAssemblaUser"] =
		{
			["create"] = false,
			["username"] = "jirauser2",
			["email"] = "jirauser2@example.com",
			["send_email"] = false,
			["fullname"] = "User 2",
		},
	},

	["commentChanges"] =
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
}
