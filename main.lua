-- Copyright (C) 2017 Robert B. Colton
-- The Pennsylvania State University

MAX_HEIGHT = 400
MIN_HEIGHT = 10
MAX_PITCH = -200
MIN_PITCH = 100

VIEW_DISTANCE = 400 -- how far to draw. More is slower but you can see further (range: 400 to 2000)

PIXEL_SCALE = 2 -- Resolution reduction. Higher number is faster, lower is better quality
PIXEL_WIDTH = love.graphics.getWidth() / PIXEL_SCALE
PIXEL_HEIGHT = love.graphics.getHeight() / PIXEL_SCALE

local doJitter = true
local doFog = true
local doSmoothing = true
local interlace = 0

local mapIndex = 1
local ctrlLock = 0
local color_R, color_G, color_B = {},{},{}
local sky_R, sky_G, sky_B = {},{},{}
local heights = {}
depth = love.graphics.getHeight() --* 0.5 -- steepness of slopes. Lower numbers = taller mountains

camera = { -- init player camera
	x = 512,
	y = 800,
	height = 100,
	angle = 0,
	v = -100
}


local mapData
local heightData
local mapWidth, mapHeight
local skyWidth, skyHeight
local height

function rayCast(line, x1, y1, x2, y2, d, xDir)
	-- x1, y1, x2, y2 are the start and end points on map for ray
	local dx = x2 - x1
	local dy = y2 - y1

	-- distance between start and end point
	local r = math.sqrt(dx * dx + dy * dy)

	local dp = math.abs(d) / 100
	local persp = 0

	-- calculate stepsize in x and y direction
	dx = dx / r
	dy = dy / r

	local ymin = height -- last place we ended drawing a vertical line
										  -- also the highest thing we've drawn to prevent over-paint (0 is max height)
	local z3 = ymin+1     -- projected Z height of point under consideration
	local data, h
	local pr=0
	local pg=0
	local pb=0
	local gap = 1 -- marks when we should break slope colour interpolation
	local hbound = height - 1

	local sx = -xDir*PIXEL_SCALE*(PIXEL_WIDTH / math.pi) + line

	-- fog parameters
	local dlimit = VIEW_DISTANCE * 0.7
	local dfog = 1 / (VIEW_DISTANCE * 0.3)
	local fo,fs = 0,1

	local x,y,idx

	-- MAIN LOOP
	-- we draw from near to far
	for i = 0,VIEW_DISTANCE do
		-- step to next position, wrapped for out-of-bounds
		x1 = math.abs((x1 + dx) % mapWidth)
		y1 = math.abs((y1 + dy) % mapHeight)
		x = math.floor(x1)
		y = math.floor(y1)
		idx = (x * mapWidth)+y

		-- get height
		h = camera.height - heights[idx]  -- lack of interpolation here causes banding artifacts close up

		-- perspective calculation where d is the correction parameter
		persp = persp + dp
		z3 = math.floor(h / persp - camera.v)


		if (i > dlimit) then -- near the fog limit
			fs = fs - dfog -- advance the fog blend by distance
			fo = fo + dfog
		end

		if (z3 < ymin) then -- this position is visible (if you wanted to mark visible/invisible positions you could do it here)
			-- write verical strip, limited to buffer bounds
			local ir = math.min(hbound, math.max(0,z3))
			local iz = math.min(hbound, ymin)

			-- read color from image
			local r,g,b = color_R[idx],color_G[idx],color_B[idx]

			-- fog effect
			if (doFog) and (i > dlimit) then -- near the fog limit
				idx = (math.floor(sx % skyWidth)*skyWidth) + (ir % skyHeight)
				r = (r * fs) + (fo * sky_R[idx])
				g = (g * fs) + (fo * sky_G[idx])
				b = (b * fs) + (fo * sky_B[idx])
				pr=r;pg=g;pb=b;
			end


			if (gap > 0) then pr=r;pg=g;pb=b; end -- no prev colors
			if (ir+1 < iz) then -- large textels, interpolate for smoothness
				-- get the next color, interpolate between that and the previous

				-- Jitter samples to make smoothing look better (otherwise orthagonal directions look stripey)
				if (doJitter) and (i < dlimit) then -- don't jitter if drawing fog
					--[ pull nearby sample to blend
					x = math.floor((x1+(dy/2))  % mapWidth)
					y = math.floor((y1+(dx/2)) % mapHeight)
					local jidx = (x*mapWidth)+y
					r = (r + color_R[jidx]) / 2
					g = (g + color_G[jidx]) / 2
				  b = (b + color_B[jidx]) / 2 --]]
				end

				if (doSmoothing) then
					local pc = (iz - ir) * 1.5 -- slight bleed between samples
					local sr = (r - pr)/pc
					local sg = (g - pg)/pc
					local sb = (b - pb)/pc
					for k = iz,ir,-1 do
						pr = pr + sr
						pg = pg + sg
						pb = pb + sb
						imageData:setPixel(line, k, pr, pg, pb, 255)
					end
				else -- no smoothing, just fill in with sample color
					for k = iz,ir,-1 do
						imageData:setPixel(line, k, r, g, b)
					end
				end

			else -- small textels. Could supersample for quality?
				pr=r;pg=g;pb=b; -- copy previous colors
				imageData:setPixel(line, ir, r, g, b)
			end
			gap = 0
		else
			gap = 1
		end
		ymin = math.min(ymin, math.floor(z3))
		if (ymin < 1) then return end -- early exit: the screen is full
	end

	-- now if we didn't get to the top of the screen, fill in with sky
	for i=ymin,0,-1 do
		idx = (math.floor(sx % skyWidth)*skyWidth) + (i % skyHeight)
		imageData:setPixel(line, i % height, sky_R[idx],sky_G[idx],sky_B[idx])
	end
end

function loadMap(index)
	-- combine height and color data
	mapData = love.image.newImageData("maps/C" .. tostring(index) .. "W.png")
	heightData = love.image.newImageData("maps/C" .. tostring(index) .. "D.png")
	--map = {}
	color_R = {}
	color_G = {}
	color_B = {}
	heights = {}
	local iw = mapData:getWidth()
	local ih = mapData:getHeight()
	for x = 0,iw+1 do -- we overscan slightly to remove some bounds checks from the rayCast function
		--map[x] = {}
		--heights[x] = {}
		for y = 0,ih+1 do
			local r,g,b = mapData:getPixel(x % iw, y % ih)
			-- since the heightmap is black/white the r,g,b values of every pixel will be equal
			-- and between 0 and 255 so we can just use the first red value to interpret the height
			local h = heightData:getPixel(x % iw, y % ih)
			local idx = (x*iw)+y
			-- mapping to a single number, needs bitwise unpacking later
			color_R[idx] = r
			color_G[idx] = g
			color_B[idx] = b
			--map[idx] = bit.bor(bit.lshift(r, 16), bit.bor(bit.lshift(g, 8), b))
			heights[idx] = h
		end
	end
	mapWidth = mapData:getWidth()
	mapHeight = mapData:getHeight()
	height = imageData:getHeight()
end

function love.load()
	love.window.setTitle("Voxel Terrain")
	--love.mouse.setVisible(false)

	hud = love.graphics.newImage("hud.png")
	sky = love.image.newImageData("sky.png")
	imageData = love.image.newImageData(PIXEL_WIDTH, PIXEL_HEIGHT)


	skyWidth = sky:getWidth()
	skyHeight = sky:getHeight()
	for x = 0,skyWidth+1 do
		for y = 0,skyHeight+1 do
			local idx = (x*skyWidth)+y
			local r,g,b = sky:getPixel(x % skyWidth, y % skyHeight)

			sky_R[idx] = r
			sky_G[idx] = g
			sky_B[idx] = b
		end
	end

	loadMap(1)
end

function love.keyreleased(key)
	if key == "escape" then
		love.event.quit()
	end
end

function love.update(dt)
	-- camera controls
	if love.keyboard.isDown("a") then
		camera.angle = camera.angle + 0.05
	end
	if love.keyboard.isDown("d") then
		camera.angle = camera.angle - 0.05
	end
	if love.keyboard.isDown("w") then
		camera.x = camera.x - 3 * math.sin(camera.angle)
		camera.y = camera.y - 3 * math.cos(camera.angle)
	end
	if love.keyboard.isDown("s") then
		camera.x = camera.x + 3 * math.sin(camera.angle)
		camera.y = camera.y + 3 * math.cos(camera.angle)
	end
	if love.keyboard.isDown("q") and camera.height < MAX_HEIGHT then
		camera.height = camera.height + 2
	end
	if love.keyboard.isDown("e") and camera.height > MIN_HEIGHT then
		camera.height = camera.height - 2
	end
	if love.keyboard.isDown("up") and camera.v < MIN_PITCH then
		camera.v = camera.v + 2
	end
	if love.keyboard.isDown("down") and camera.v > MAX_PITCH then
		camera.v = camera.v - 2
	end

	-- UI toggles (rate limited)
	local latchCount = 0
	if love.keyboard.isDown("return") then
		latchCount = latchCount + 1
		if (ctrlLock < 1) then
			ctrlLock = 1
			mapIndex = mapIndex + 1
			if (mapIndex > 4) then mapIndex = 1 end
			loadMap(mapIndex)
		end
	end
	if love.keyboard.isDown("j") then
		latchCount = latchCount + 1
		if (ctrlLock < 1) then
			ctrlLock = 1
			doJitter = not doJitter
		end
	end
	if love.keyboard.isDown("f") then
		latchCount = latchCount + 1
		if (ctrlLock < 1) then
			ctrlLock = 1
			doFog = not doFog
		end
	end
	if love.keyboard.isDown("m") then
		latchCount = latchCount + 1
		if (ctrlLock < 1) then
			ctrlLock = 1
			doSmoothing = not doSmoothing
		end
	end

	if (latchCount < 1) then ctrlLock = 0 end
end

function love.draw()
	-- draw terrain
	local sinAngle = math.sin(camera.angle)
	local cosAngle = math.cos(camera.angle)

	local y3d = -depth * 1.5
	for i = interlace,imageData:getWidth()-1,2 do -- increment by 2 for interlacing
		local x3d = (i - imageData:getWidth() / 2) * 2.25

		local rotX =  cosAngle * x3d + sinAngle * y3d
		local rotY = -sinAngle * x3d + cosAngle * y3d

		rayCast(i, camera.x, camera.y, camera.x + rotX, camera.y + rotY, y3d / math.sqrt(x3d * x3d + y3d * y3d), camera.angle)
	end

	-- alternate scanlines each frame
	interlace = 1 - interlace

	if not bufferImage then bufferImage = love.graphics.newImage(imageData)
	else bufferImage:refresh() end

	love.graphics.draw(bufferImage, 0, 0, 0, PIXEL_SCALE)

	-- draw hud and altimeter
	--love.graphics.draw(hud, 0, 0)

	love.graphics.setColor(0, 0, 0)
	love.graphics.print("Map: "..mapIndex.." FPS: "..tostring(love.timer.getFPS()).."\n"..
	"X: "..tostring(camera.x).."\n"..
	"Y: "..tostring(camera.y).."\n"..
	"[J]itter: "..tostring(doJitter).."; [F]og: "..tostring(doFog)..
	"; S[m]oothing: "..tostring(doSmoothing),
	10, 10)
	love.graphics.setColor(255, 255, 255)
end
