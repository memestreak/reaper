-- loop_media_item.lua
--
-- Automatically set loop points to selected region when loop
-- mode is activated.

-- =====================================================================
--  -1 == query, 0=clear, 1=set, >1=toggle . returns new value
-- ====================================================================
repeat_state = 1 - reaper.GetSetRepeat(-1)
reaper.GetSetRepeat(repeat_state)

if repeat_state ~= 1 then
  -- We've turned off repeat. All done.
  return
end

-- Get the current time selection
time_selection_start, time_selection_end =
   reaper.GetSet_LoopTimeRange(false,  -- isSet
                               false,  -- isLoop
                               0,      -- start
                               0,      -- end
                               false)  -- allowautoseek

if time_selection_start ~= time_selection_end then
  -- We have an existing time selection. We're done!
  return
end

selected_item_count = reaper.CountSelectedMediaItems(0)
if selected_item_count == 0 then
  -- Nothing to base a time selection on. We're done.
  return
end

-- Get the first selected media item
media_item = reaper.GetSelectedMediaItem(0, 0)

-- Get the item start and length
item_start = reaper.GetMediaItemInfo_Value(media_item, "D_POSITION")
item_length = reaper.GetMediaItemInfo_Value(media_item, "D_LENGTH")
item_end = item_start + item_length

-- Set time selection to the item start and end
reaper.GetSet_LoopTimeRange(true, false, item_start, item_end, false)


