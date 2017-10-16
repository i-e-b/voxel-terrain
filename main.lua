local MAX_HEIGHT = 400
local MIN_HEIGHT = 10
local MAX_PITCH = -200
local MIN_PITCH = 150

local VIEW_DISTANCE = 600 -- how far to draw. More is slower but you can see further (range: 400 to 2000)

local PIXEL_SCALE = 3 -- Resolution reduction. Higher number is faster, lower is better quality
local PIXEL_WIDTH = love.graphics.getWidth() / PIXEL_SCALE
local PIXEL_HEIGHT = love.graphics.getHeight() / PIXEL_SCALE

local doJitter = true
local doFog = true
local doSmoothing = true
local interlace = 0

local mapIndex = 1
local ctrlLock = 0
local color_R, color_G, color_B = {},{},{}
local sky_R, sky_G, sky_B = {},{},{}
local heights = {}
local depth = love.graphics.getHeight() -- steepness of slopes. Lower numbers = taller mountains

local camera = { -- init player camera
	x = 512,
	y = 800,
	height = 100,
	angle = 0,
	v = 0
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


	local dp = math.abs(d) / 100
	local persp = 0

	-- calculate stepsize in x and y direction
	local dr = math.sqrt(dx * dx + dy * dy) -- distance between start and end point
	dx = dx / dr
	dy = dy / dr

	local ymin = height -- last place we ended drawing a vertical line
										  -- also the highest thing we've drawn to prevent over-paint (0 is max height)
	local z3 = ymin+1     -- projected Z height of point under consideration
	local data, h
	local pr,pg,pb=0,0,0
	local gap = 1 -- marks when we should break slope colour interpolation
	local hbound = height - 1

	local sx = math.floor( (-xDir*PIXEL_SCALE*(PIXEL_WIDTH / math.pi) + line) % skyWidth)*skyWidth

	-- fog parameters
	local dlimit = VIEW_DISTANCE * 0.7
	local dfog = 1 / (VIEW_DISTANCE * 0.3)
	local fo,fs = 0,1
	local lastI = 0

	local x,y,idx

	-- local references to speed up the core loop: (this is surprisingly effective)
	local abs = math.abs
	local floor = math.floor
	local min = math.min
	local max = math.max
	local camHeight = camera.height
	local camV = camera.v

	-- MAIN LOOP
	-- we draw from near to far
	-- first we do a tight loop through the height map looking for a position
	-- that would be visible behind anything else we've drawn
	-- then we loop through the pixels to draw and color them
	for i = 0,VIEW_DISTANCE do
		-- step to next position, wrapped for out-of-bounds
		x1 = abs((x1 + dx) % mapWidth)
		y1 = abs((y1 + dy) % mapHeight)
		x = floor(x1)
		y = floor(y1)

		-- get height
		idx = (x * mapWidth) + y
		h = camHeight - heights[idx]  -- lack of interpolation here causes banding artifacts close up

		-- perspective calculation where d is the correction parameter
		persp = persp + dp
		z3 = h / persp - camV

		-- is this position is visible?
		if (z3 < ymin) then -- (if you wanted to mark visible/invisible positions you could do it here)
			z3 = floor(z3) -- get on to pixel bounds

			-- bounds of vertical strip, limited to buffer bounds
			local ir = min(hbound, max(0,z3))
			local iz = min(hbound, ymin)

			-- read color from image
			local r,g,b = color_R[idx],color_G[idx],color_B[idx]

			-- fog effect
			if (doFog) and (i > dlimit) then -- near the fog limit
				fo = dfog*(i-dlimit) -- calculate the fog blend by distance
				fs = 1 - fo
				idx = (sx) + (ir % skyHeight)
				r = (r * fs) + (fo * sky_R[idx])
				g = (g * fs) + (fo * sky_G[idx])
				b = (b * fs) + (fo * sky_B[idx])
			end

			if (ir+1 < iz) then -- large textels, interpolate for smoothness
				-- get the next color, interpolate between that and the previous

				-- Jitter samples to make smoothing look better (otherwise orthagonal directions look stripey)
				if (doJitter) and (i < dlimit) then -- don't jitter if drawing fog
					-- pull nearby sample to blend
					x = floor((x1+(dy/2))  % mapWidth)
					y = floor((y1+(dx/2)) % mapHeight)
					local jidx = (x*mapWidth)+y
					r = (r + color_R[jidx]) / 2
					g = (g + color_G[jidx]) / 2
				  b = (b + color_B[jidx]) / 2
				end

				if (doSmoothing) then
					if (gap > 0) then pr=r;pg=g;pb=b; end -- no prev colors
					local pc = (iz - ir) + 1
					local sr = (r - pr)/pc
					local sg = (g - pg)/pc
					local sb = (b - pb)/pc
					for k = iz,ir,-1 do
						imageData:setPixel(line, k, pr, pg, pb)
						pr = pr + sr
						pg = pg + sg
						pb = pb + sb
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
		ymin = min(ymin, z3)
		if (ymin < 1) then return end -- early exit: the screen is full
	end

	-- now if we didn't get to the top of the screen, fill in with sky
	for i=ymin,0,-1 do
		idx = (sx) + (i % skyHeight)
		imageData:setPixel(line, i % height, sky_R[idx],sky_G[idx],sky_B[idx])
	end
end

function loadMap(index)
	-- extract height and color data
	mapData = love.image.newImageData("maps/C" .. tostring(index) .. "W.png")
	heightData = love.image.newImageData("maps/C" .. tostring(index) .. "D.png")

	color_R = {}
	color_G = {}
	color_B = {}
	heights = {0,0,0,0}
	local iw = mapData:getWidth()
	local ih = mapData:getHeight()
	for x = 0,iw+1 do -- we overscan slightly to remove some bounds checks from the rayCast function
		for y = 0,ih+1 do
			local idx = (x*iw)+y

			local r,g,b = mapData:getPixel(x % iw, y % ih)
			color_R[idx] = r
			color_G[idx] = g
			color_B[idx] = b

			local h = heightData:getPixel(x % iw, y % ih)
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
	bufferImage = love.graphics.newImage(imageData)

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

	bufferImage:refresh()

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
