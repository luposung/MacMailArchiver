# List of mailboxes on the server to ignore (not archived)
property mailboxesToIgnore : {"Deleted Messages", "Drafts", "Outbox", "Trash", "Junk", "Apple Mail To Do", "Contacts", "Emailed Contacts", "Chats"}
# List of mailboxes which will be have an extenstion appended to the name when archived 
property mailboxesToRename : {"INBOX", "Sent"}
# Extension to append to renamed mailboxes
property mailboxRenameExtension : "_Archive"
# Number of times it will retry archiving an email in case of a failure
property maxFail : 3
# Log file name
property logFile : "MacMailArchiver.log"

on run
	activate
	my logToFile("Starting at: " & (current date))
	set mailAccountList to {}
	tell application "Mail"
		repeat with i in every account
			set end of mailAccountList to (name of i as string)
		end repeat
	end tell
	set mailAccountName to (choose from list mailAccountList with title "MacMailArchiver" with prompt "Archive account:")
	if mailAccountName is equal to false then
		return
	else
		set mailAccountName to first item of mailAccountName
	end if
	set topLevelArchiveMailboxName to "[Archive] " & mailAccountName
	-- display a dialog to prompt the user to select number of days to archive
	set monthChoices to {"1 month", "2 months", "3 months", "6 months", "9 months", "1 year", "2 years", "3 years", "Archive all mail"}
	set monthsToArchive to (choose from list monthChoices with title "MacMailArchiver" with prompt "Archive messages older than:")
	if monthsToArchive is equal to false then
		return
	else
		set monthsToArchive to first item of monthsToArchive
	end if
	my logToFile("Archiving " & monthsToArchive)
	set archiveAll to false
	if monthsToArchive is equal to "1 month" then
		set staledate to (current date) - (30 * days)
	else if monthsToArchive is equal to "2 months" then
		set staledate to (current date) - (60 * days)
	else if monthsToArchive is equal to "3 months" then
		set staledate to (current date) - (90 * days)
	else if monthsToArchive is equal to "6 months" then
		set staledate to (current date) - (180 * days)
	else if monthsToArchive is equal to "9 months" then
		set staledate to (current date) - (270 * days)
	else if monthsToArchive is equal to "1 year" then
		set staledate to (current date) - (365 * days)
	else if monthsToArchive is equal to "2 years" then
		set staledate to (current date) - (2 * 365 * days)
	else if monthsToArchive is equal to "3 years" then
		set staledate to (current date) - (3 * 365 * days)
	else if monthsToArchive is equal to "Archive all mail" then
		set archiveAll to true
	end if
	set totalArchiveCount to 0
	tell application "Mail"
		-- activate -- we did not tell the Finder to activate. This means that the app didn't need to become the frontmost application
		-- delay 1
		my mailSelectMailbox(inbox)
		display notification "This may take a while..." with title "MacMailArchiver" subtitle "Starting up"
		repeat with nextAccount in every account
			if (name of nextAccount as string) is equal to mailAccountName then
				repeat with sourceMailbox in every mailbox of nextAccount
					set sourceMailboxName to name of sourceMailbox as string
					set sourceContainer to container of sourceMailbox
					if (class of sourceContainer is container) then
						set isMailboxRoot to false
					else
						set isMailboxRoot to true
					end if
					if sourceMailboxName is in mailboxesToIgnore and isMailboxRoot then
						my logToFile("Ignoring mailbox: " & sourceMailboxName)
					else
						my logToFile("Mailbox: " & sourceMailboxName)
						try
							with timeout of (60 * minutes) seconds
								-- display notification "Selecting messages to archive. This can take a while for large mailboxes." with title "Selecting Messages" subtitle "Mailbox: " & sourceMailboxName
								if archiveAll is true then
									set messagesToArchive to (every message of sourceMailbox whose deleted status is false)
								else
									set messagesToArchive to (every message of sourceMailbox whose date received is less than staledate and deleted status is false)
								end if
								set countToArchive to count of messagesToArchive
							end timeout
						on error errStr number errorNumber -- error creating mailbox
							if errorNumber = -128 then -- User cancelled
								my logToFile("User cancelled while scanning mailbox: " & sourceMailboxName)
							else
								my logToFile("Timeout error")
								tell application "System Events"
									display dialog "Timed out archiving mailbox: " & sourceMailboxName & ". Try archiving older messages first or manually archiving this mailbox."
								end tell
							end if
							display notification "Terminated due to error occured." with title "MacMailArchiver" subtitle "Terminated"
							return errorNumber & errStr
						end try
						if countToArchive > 0 then
							-- Found messages to archive in this folder
							my logToFile("Archive count: " & countToArchive)
							if not isMailboxRoot then
								-- Mailbox has parent mailbox (not root)
								my logToFile("Mailbox: " & sourceMailboxName & " has container: " & name of sourceContainer)
								-- Map mailbox hierarchy
								set parentList to {}
								set nextContainer to sourceMailbox
								repeat
									set the beginning of parentList to (name of nextContainer)
									set nextContainer to container of nextContainer
									if (class of nextContainer is not container) then
										set the beginning of parentList to topLevelArchiveMailboxName
										exit repeat
									end if
								end repeat
								-- Create mailbox heirarchy
								set archiveMailboxName to ""
								repeat with nextItem in parentList
									if archiveMailboxName is "" then
										set archiveMailboxName to nextItem
									else
										set archiveMailboxName to archiveMailboxName & "/" & nextItem
									end if
									my logToFile("Check mailbox: " & archiveMailboxName)
									set failCount to 0
									if not (exists mailbox archiveMailboxName) then
										repeat -- repeat trying to create mailbox in case it fails
											my logToFile("Make mailbox: " & archiveMailboxName)
											try -- try to make mailbox
												make new mailbox with properties {name:archiveMailboxName & "/"}
												exit repeat -- exit if create mailbox successfully																	
											on error errStr number errorNumber -- error creating mailbox
												if errorNumber = -128 then -- User cancelled
													my logToFile("User cancelled while creating mailbox: " & archiveMailboxName)
													display notification "Terminated due to error occured." with title "MacMailArchiver" subtitle "Terminated"
													return errorNumber
												end if
												my logToFile("error: " & errStr & " creating mailbox: " & archiveMailboxName)
												my mailSelectMailbox(inbox)
												set failCount to failCount + 1
												if failCount > maxFail then -- too many failures
													my logToFile("Exit after " & failCount & " failures")
													display notification "Terminated due to error occured." with title "MacMailArchiver" subtitle "Terminated"
													return -- EXIT APPLICATION
												end if
											end try
										end repeat -- retry repeat
									end if
									my mailSelectMailbox(mailbox archiveMailboxName)
								end repeat
							else
								-- Mailbox doesn't have parent	
								if sourceMailboxName is in mailboxesToRename then
									my logToFile("Archive mailbox: " & sourceMailboxName)
									set archiveMailboxName to sourceMailboxName & mailboxRenameExtension
								else
									my logToFile("Root mailbox: " & sourceMailboxName)
									set archiveMailboxName to sourceMailboxName
								end if
								set archiveMailboxName to topLevelArchiveMailboxName & "/" & archiveMailboxName
								if not (exists mailbox archiveMailboxName) then
									repeat -- repeat trying to create mailbox in case it fails
										set failCount to 0
										try -- try to make mailbox
											make new mailbox with properties {name:archiveMailboxName & "/"}
											exit repeat -- exit if create mailbox successfully
										on error errStr number errorNumber -- error creating mailbox
											if errorNumber = -128 then -- User cancelled
												my logToFile("User cancelled while creating mailbox: " & archiveMailboxName)
												display notification "Terminated due to error occured." with title "MacMailArchiver" subtitle "Terminated"
												return errorNumber
											end if
											my logToFile("error: " & errStr & " creating mailbox: " & archiveMailboxName)
											--set selected mailboxes of message viewer 1 to {inbox}
											my mailSelectMailbox(inbox)
											set failCount to failCount + 1
											if failCount > maxFail then -- too many failures
												my logToFile("Exit after " & failCount & " failures")
												display notification "Terminated due to error occured." with title "MacMailArchiver" subtitle "Terminated"
												return -- EXIT APPLICATION
											end if
										end try
									end repeat -- retry repeat
								end if
								my mailSelectMailbox(mailbox archiveMailboxName)
							end if
							-- Archive messages from sourceMailbox to archiveMailbox
							set archiveMailbox to mailbox archiveMailboxName
							my logToFile("Archiving: " & countToArchive & " messages from: " & sourceMailboxName & " to: " & archiveMailboxName)
							display notification "Archiving " & countToArchive & " emails..." with title "MacMailArchiver" subtitle "Mailbox: " & sourceMailboxName
							set movedCount to 0
							repeat with nextMessage in messagesToArchive -- move messages from source to archive
								repeat -- retry message move maxFail times before giving up
									set failCount to 0
									try -- try moving the message
										move nextMessage to archiveMailbox
										set movedCount to movedCount + 1
										set totalArchiveCount to totalArchiveCount + 1
										exit repeat -- exit if create mailbox successfully
									on error errStr number errorNumber -- error moving the message
										if errorNumber = -128 then -- User cancelled
											my logToFile("User cancelled while copying messages to mailbox: " & archiveMailboxName)
											display notification "Terminated due to error occured." with title "MacMailArchiver" subtitle "Terminated"
											return errorNumber
										end if
										my logToFile("Error: " & errStr & " moving message to: " & archiveMailboxName)
										set failCount to failCount + 1
										if failCount > maxFail then -- too many failures
											my logToFile("Exit after " & failCount & " failures")
											display notification "Terminated due to error occured." with title "MacMailArchiver" subtitle "Terminated"
											return -- EXIT APPLICATION
										end if
									end try
								end repeat -- retry repeat
								if movedCount mod 100 is equal to 0 then
									display notification "Archived " & movedCount & " of " & countToArchive & " emails" with title "MacMailArchiver" subtitle sourceMailboxName
								end if
							end repeat
						end if
					end if
				end repeat
				display notification "Archived " & totalArchiveCount & " emails..." with title "MacMailArchiver" subtitle "Completed email archive"
			end if
		end repeat
	end tell
	(* if totalArchiveCount > 0 then
		tell application "System Events"
			display dialog "Select \"Erase Deleted Items\" from the Mailbox menu to purge the archived emails from the server."
		end tell
	end if *)
	my logToFile("Archived : " & totalArchiveCount)
	my logToFile("Done at: " & (current date))
end run

on mailSelectMailbox(theMailbox)
	tell application "Mail"
		try
			if (count of message viewers) is 0 then
				make new message viewer at beginning of message viewers
			end if
			set selected mailboxes of message viewer 1 to theMailbox
		end try
	end tell
end mailSelectMailbox

on logToFile(logData)
	log (logData)
	set the logPath to ((path to library folder from user domain) as string) & "Logs:" & logFile
	try
		set the openFile to open for access file logPath with write permission
		write (logData as string) & linefeed to the openFile starting at eof as Çclass utf8È
		close access the openFile
		return true
	on error
		try
			close access file logPath
		end try
		return false
	end try
end logToFile