




--- Holds all the defined mazes as an array
local g_Mazes = {};

--- X/Z Size of the generated maze, in each direction from the center
local MAZE_SIZE = 10;

--- Height for the maze, halved
local MAZE_HEIGHT = 5;




--- Toggles a few doors in a single maze
function ToggleMazeDoors(a_Maze)
	for i = 0, 15 do
		local rndx = math.random(2 * MAZE_SIZE);
		local rndz = math.random(2 * MAZE_SIZE);
		local Height = a_Maze.Height[rndz][rndx];
		if (Height >= 0) then
			local BlockX = a_Maze.Center.x + rndx - MAZE_SIZE;
			local BlockZ = a_Maze.Center.z + rndz - MAZE_SIZE;

			-- TODO: We have no cWorld:ToggleDoor() API, we need to do it by hand:
			local BlockValid, BlockType, BlockMeta = a_Maze.World:GetBlockTypeMeta(BlockX, Height + 2, BlockZ);
			if (BlockValid and (BlockType == E_BLOCK_WOODEN_DOOR)) then
				if (BlockMeta == 8) then
					BlockMeta = 9;
				else
					BlockMeta = 8;
				end
				a_Maze.World:SetBlockMeta(BlockX, Height + 2, BlockZ, BlockMeta);
			end
		end
	end
end





function OnWorldTick(a_World, a_Dt, a_LastTickDuration)
	-- TODO: Toggle some of mazes' doors
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
	Maze.Center = a_MazeCenter;
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

	Maze.Height = {};
	local NumDoorsPlaced = 0;
	for z = 0, 2 * MAZE_SIZE do
		local BlockZ = MinZ + z;
		Maze.Height[z] = {};
		for x = 0, 2 * MAZE_SIZE do
			local BlockX = MinX + x;
			local Height = FindMazeHeight(WorldImage, BlockX, BlockZ, CenterY);
			Maze.Height[z][x] = Height;
			if (Height >= 0) then
				-- TODO: Randomize the door placement
				Height = MinY + Height;
				-- Generate a psaudorandom value that is always the same for the same X/Z pair, but is otherwise random enough:
				-- This is actually similar to how MCServer does its noise functions
				local PseudoRandom = (((BlockX * 7) % 17) * ((x + 10) % 13) + (BlockZ % 9)) * 13 + Height;
				WorldImage:SetBlockTypeMeta(BlockX, Height,     BlockZ, E_BLOCK_WOODEN_DOOR, (PseudoRandom / 6) % 8);
				WorldImage:SetBlockTypeMeta(BlockX, Height + 1, BlockZ, E_BLOCK_WOODEN_DOOR, 8 + (PseudoRandom % 2));
				NumDoorsPlaced = NumDoorsPlaced + 1;
			end
		end
	end
	
	if (NumDoorsPlaced < MAZE_SIZE * MAZE_SIZE) then
		-- Less than 1/4 of the maze space has been set with doors, don't consider this a maze
		local Percentage = 100 * NumDoorsPlaced / (4 * MAZE_SIZE * MAZE_SIZE);
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
		a_Player:SendMessage("Maze created.");
	end
	
	return true;
end





cPluginManager.AddHook(cPluginManager.HOOK_WORLD_TICK, OnWorldTick);
cPluginManager.BindCommand("/doormaze", "doormaze.create", HandleDoorMazeCommand, " - Creates a door maze around the specified player");





