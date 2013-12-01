




--- Holds all the defined mazes as an array
local g_Mazes = {};

--- X/Z Size of the generated maze, in each direction from the center
local MAZE_SIZE = 10;

--- Height for the maze, halved
local MAZE_HEIGHT = 5;

--- Number of doors to change at once
local MAZE_CHANGES = 50;

--- Name of the file where to save and load the mazes from / to
local MAZE_FILE = "doormazes.xml";




function SaveMazes()
	-- TODO: Find a proper XML-writing library for this
	local f, err = io.open(MAZE_FILE, "w");
	if (f == nil) then
		LOGWARNING("DoorMaze: Cannot save mazes to '" .. MAZE_FILE .. "': " .. err);
		return;
	end
	f:write([[<?xml version="1.0" encoding="ISO-8859-1"?>]]);
	f:write("\n<mazes>\n");
	for idx, maze in ipairs(g_Mazes) do
		f:write("<maze worldname='", maze.World:GetName(), "'>");
		f:write("<center x='", maze.Center.x, "' y='", maze.Center.y, "' z='", maze.Center.z, "'/>\n");
		f:write("<doors>\n");
		for idx2, door in ipairs(maze.Doors) do
			f:write("<door x='", door.x, "' y='", door.y, "' z='", door.z, "'/>\n");
		end
		f:write("</doors></maze>");
	end
	f:write("</mazes>");
	f:close();
end





function LoadMazes()
	if not(cFile:Exists(MAZE_FILE)) then
		return;
	end
	
	local CurrentMaze = {};
	local Mazes = {};  -- List of all the loaded mazes, will replace g_Mazes if successfully loaded
	local Callbacks =
	{
		StartElement = function (a_Parser, a_Name, a_Attrib)
			if (a_Name == "maze") then
				CurrentMaze =
				{
					Doors = {},
					NumTicksLeft = 50,
				};
				CurrentMaze.World = cRoot:Get():GetWorld(a_Attrib.worldname);
				if (CurrentMaze.World == nil) then
					LOGINFO("Dropping maze, because world '" .. tostring(a_Attrib.worldname or "") .. "' cannot be found.");
					-- The actual drop will happen on "</maze>"
				end
			elseif (a_Name == "center") then
				CurrentMaze.Center = Vector3i(tonumber(a_Attrib.x), tonumber(a_Attrib.y), tonumber(a_Attrib.z));
			elseif (a_Name == "door") then
				table.insert(CurrentMaze.Doors, { x = tonumber(a_Attrib.x), y = tonumber(a_Attrib.y), z = tonumber(a_Attrib.z) });
			end
		end,
		
		EndElement = function (a_Parser, a_Name)
			if (a_Name == "maze") then
				if (CurrentMaze.World ~= nil) then
					table.insert(Mazes, CurrentMaze);
				end
			end
		end,
	};
	local Parser = lxp.new(Callbacks);
	local f, err = io.open(MAZE_FILE, "r");
	if (f == nil) then
		LOGWARNING("Cannot read mazes from '" .. MAZE_FILE .. "': " .. err);
		return;
	end
	local Success, ErrMsg = Parser:parse(f:read("*all"));
	f:close();
	if not(Success) then
		LOGWARNING("Cannot parse mazes from '" .. MAZE_FILE .. "': " .. ErrMsg);
		return;
	end
	Parser:close();
	
	-- Successfully loaded and parsed, set into g_Mazes:
	g_Mazes = Mazes;
end





--- Toggles a few doors in a single maze
function ToggleMazeDoors(a_Maze)
	for i = 0, MAZE_CHANGES do
		local rnd = math.random(#a_Maze.Doors);
		local BlockX = a_Maze.Doors[rnd].x;
		local BlockY = a_Maze.Doors[rnd].y;
		local BlockZ = a_Maze.Doors[rnd].z;

		-- TODO: We have no cWorld:ToggleDoor() API, we need to do it by hand:
		local BlockValid, BlockType, BlockMeta = a_Maze.World:GetBlockTypeMeta(BlockX, BlockY, BlockZ);
		if (BlockValid and (BlockType == E_BLOCK_WOODEN_DOOR)) then
			if (BlockMeta == 8) then
				BlockMeta = 9;
			else
				BlockMeta = 8;
			end
			a_Maze.World:SetBlockMeta(BlockX, BlockY, BlockZ, BlockMeta);
		end
	end
end





function OnWorldTick(a_World, a_Dt, a_LastTickDuration)
	-- Toggle some of mazes' doors:
	for idx, maze in ipairs(g_Mazes) do
		if (maze.World == a_World) then
			-- Check if it's late enough after the last toggle:
			if (maze.NumTicksLeft > 0) then
				maze.NumTicksLeft = maze.NumTicksLeft - 1;
			else
				maze.NumTicksLeft = a_LastTickDuration / 2;  -- The more msec per tick, the slower the doors are changed
				
				-- Check if there's a player in or near the maze, toggle doors only if so:
				local IsActive = false;
				maze.World:ForEachPlayer(
					function (a_Player)
						local PlayerPos = a_Player:GetPosition();
						if (
							(PlayerPos.x >= maze.Center.x - 2 * MAZE_SIZE) and
							(PlayerPos.x <= maze.Center.x + 2 * MAZE_SIZE) and
							(PlayerPos.z >= maze.Center.z - 2 * MAZE_SIZE) and
							(PlayerPos.z <= maze.Center.z + 2 * MAZE_SIZE)
						) then
							IsActive = true;
							return true;
						end
					end
				);
				
				if (IsActive) then
					ToggleMazeDoors(maze);
				end
			end
		end
	end  -- for maze - g_Mazes[]
end





--- Returns the height at which to place the door at the specified coord
function FindMazeHeight(a_WorldImage, a_BlockX, a_BlockZ, a_CenterY)
	for y = 0, MAZE_HEIGHT do
		if (
			(a_WorldImage:GetBlockType(a_BlockX, a_CenterY + y, a_BlockZ) == E_BLOCK_AIR) and
			(a_WorldImage:GetBlockType(a_BlockX, a_CenterY + y + 1, a_BlockZ) == E_BLOCK_AIR) and
			g_BlockIsSolid[a_WorldImage:GetBlockType(a_BlockX, a_CenterY + y - 1, a_BlockZ)]
		) then
			return y + MAZE_HEIGHT;
		end
		if (
			(a_WorldImage:GetBlockType(a_BlockX, a_CenterY - y, a_BlockZ) == E_BLOCK_AIR) and
			(a_WorldImage:GetBlockType(a_BlockX, a_CenterY - y + 1, a_BlockZ) == E_BLOCK_AIR) and
			g_BlockIsSolid[a_WorldImage:GetBlockType(a_BlockX, a_CenterY - y - 1, a_BlockZ)]
		) then
			return MAZE_HEIGHT - y;
		end
	end
	return -1;
end





--- Generates and returns new a maze around the specified center
function GenerateMaze(a_World, a_MazeCenter)
	local Maze = {};
	a_MazeCenter.x = math.floor(a_MazeCenter.x);
	a_MazeCenter.z = math.floor(a_MazeCenter.z);
	Maze.Center = Vector3i(a_MazeCenter);
	Maze.World = a_World;
	Maze.NumTicksLeft = 50;
	
	local CenterY = math.floor(a_MazeCenter.y);
	local MinX = a_MazeCenter.x - MAZE_SIZE;
	local MaxX = MinX + 2 * MAZE_SIZE;
	local MinY = CenterY - MAZE_HEIGHT;
	local MaxY = CenterY + MAZE_HEIGHT;
	local MinZ = a_MazeCenter.z - MAZE_SIZE;
	local MaxZ = MinZ + 2 * MAZE_SIZE;

	local WorldImage = cBlockArea();
	if not(WorldImage:Read(a_World, MinX, MaxX, MinY, MaxY, MinZ, MaxZ)) then
		return nil, "Cannot create maze: block area reading failed";
	end

	Maze.Doors = {};
	for z = 0, 2 * MAZE_SIZE do
		local BlockZ = MinZ + z;
		for x = 0, 2 * MAZE_SIZE do
			local BlockX = MinX + x;
			local Height = FindMazeHeight(WorldImage, BlockX, BlockZ, CenterY);
			if (Height >= 0) then
				-- TODO: Randomize the door placement
				Height = MinY + Height;
				-- Generate a psaudorandom value that is always the same for the same X/Z pair, but is otherwise random enough:
				-- This is actually similar to how MCServer does its noise functions
				local PseudoRandom = (((BlockX * 7) % 17) * ((x + 10) % 13) + (BlockZ % 9)) * 13 + Height;
				WorldImage:SetBlockTypeMeta(BlockX, Height,     BlockZ, E_BLOCK_WOODEN_DOOR, (PseudoRandom / 6) % 8);
				WorldImage:SetBlockTypeMeta(BlockX, Height + 1, BlockZ, E_BLOCK_WOODEN_DOOR, 8 + (PseudoRandom % 2));
				
				-- Insert the top door block into the list of maze's doors
				table.insert(Maze.Doors, {x = BlockX, y = Height + 1, z = BlockZ} );
			end
		end
	end
	
	if (#Maze.Doors < MAZE_SIZE * MAZE_SIZE) then
		-- Less than 1/4 of the maze space has been set with doors, don't consider this a maze
		local Percentage = 100 * #Maze.Doors / (4 * MAZE_SIZE * MAZE_SIZE);
		return nil, "Cannot create maze: terrain not even enough, only " .. tostring(Percentage) .. " % can be mazed.";
	end
	
	WorldImage:Write(a_World, MinX, MinY, MinZ);
	return Maze;
end





function HandleDoorMazeCommand(a_Split, a_Player)
	local MazeCenter = a_Player:GetPosition();
	local World = a_Player:GetWorld();
	if (#a_Split > 1) then
		local HasFound = false;
		cRoot:Get():FindAndDoWithPlayer(a_Split[2],
			function (a_DstPlayer)
				HasFound = true;
				MazeCenter = a_DstPlayer:GetPosition();
				World = a_DstPlayer:GetWorld();
			end
		);
		if not(HasFound) then
			a_Player:SendMessage("Player " .. a_Split[2] .. " not found.");
			return;
		end
	end
	
	local Maze, err = GenerateMaze(World, MazeCenter);
	if (Maze == nil) then
		a_Player:SendMessage(err);
	else
		table.insert(g_Mazes, Maze);
		SaveMazes();
		a_Player:SendMessage("Maze created.");
	end
	
	return true;
end





function OnPlayerRightClick(a_Player, a_BlockX, a_BlockY, a_BlockZ, a_BlockFace)
	-- The player is right-clicking a block, prevent them from toggling maze's doors:
	for idx, maze in ipairs(g_Mazes) do
		if (maze.World == a_Player:GetWorld()) then
			if (
				(a_BlockX >= maze.Center.x - MAZE_SIZE) and
				(a_BlockX <= maze.Center.x + MAZE_SIZE) and
				(a_BlockZ >= maze.Center.z - MAZE_SIZE) and
				(a_BlockZ <= maze.Center.z + MAZE_SIZE) and
				(a_BlockY >= maze.Center.y - MAZE_HEIGHT) and
				(a_BlockY <= maze.Center.y + MAZE_HEIGHT)
			) then
				-- The clicked block is within the maze's coords. Check each maze door:
				for idx2, door in ipairs(maze.Doors) do
					if (
						(door.x == a_BlockX) and
						(door.z == a_BlockZ) and
						(
							(door.y == a_BlockY) or (door.y == a_BlockY + 1)  -- The door is 2 blocks high, the stored coord is for the upper part
						)
					) then
					
						-- It is my door, how dare you touch it!?
						a_Player:SendMessage("Don't touch the maze doors!");
						
						-- The client already thinks the door is toggled, let them know it's not (need to send both door blocks):
						local IsValid1, BlockType1, BlockMeta1 = a_Player:GetWorld():GetBlockTypeMeta(a_BlockX, door.y - 1, a_BlockZ);
						if (IsValid1) then
							local IsValid2, BlockType2, BlockMeta2 = a_Player:GetWorld():GetBlockTypeMeta(a_BlockX, door.y, a_BlockZ);
							if (IsValid2) then
								a_Player:GetClientHandle():SendBlockChange(a_BlockX, door.y - 1, a_BlockZ, BlockType1, BlockMeta1);
								a_Player:GetClientHandle():SendBlockChange(a_BlockX, door.y,     a_BlockZ, BlockType2, BlockMeta2);
							end
						end
						
						return true;
					end
				end  -- for door - maze.Doors[]
			end  -- if (in maze)
		end  -- if (in maze world)
	end  -- for maze - g_Mazes[]
	return false;
end





-- The main initialization goes here:
LoadMazes();
cPluginManager.AddHook(cPluginManager.HOOK_WORLD_TICK, OnWorldTick);
cPluginManager.AddHook(cPluginManager.HOOK_PLAYER_RIGHT_CLICK, OnPlayerRightClick);
cPluginManager.BindCommand("/doormaze", "doormaze.create", HandleDoorMazeCommand, " - Creates a door maze around the specified player");





