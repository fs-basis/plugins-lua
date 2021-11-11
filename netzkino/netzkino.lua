--[[
	Netzkino-Plugin

	The MIT License (MIT)

	Copyright (c) 2014 Marc Szymkowiak 'Ezak91' marc.szymkowiak91@googlemail.com
	for release-version

	Copyright (c) 2014 micha_bbg, svenhoefer, bazi98 an many other db2w-user
	with hints and codesniplets for db2w-Edition

	Changed to internal curl	by BPanther, 10. Feb 2019
	Changed to new URL		by BPanther, 01. Nov 2021
	Some optimisations		by BPanther, 03. Nov 2021
	Some optimisations		by BPanther, 11. Nov 2021

	Permission is hereby granted, free of charge, to any person obtaining a copy
	of this software and associated documentation files (the "Software"), to deal
	in the Software without restriction, including without limitation the rights
	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
	copies of the Software, and to permit persons to whom the Software is
	furnished to do so, subject to the following conditions:
	The above copyright notice and this permission notice shall be included in all
	copies or substantial portions of the Software.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
	SOFTWARE.
]]

caption = "Netzkino HD"
netzkino_png = arg[0]:match('.*/') .. "/netzkino.png"
local json = require "json"
local base_url = "http://api.netzkino.de.simplecache.net/capi-2.0a/"

--Objekte
function script_path()
	local str = debug.getinfo(2, "S").source:sub(2)
	return str:match("(.*/)")
end

ret = nil -- global return value
function key_home(a)
	ret = MENU_RETURN["EXIT"]
	return ret
end

function key_setup(a)
	ret = MENU_RETURN["EXIT_ALL"]
	return ret
end

function getdata(Url, output, timeout)
	if Url == nil then return nil end
	if Curl == nil then
		Curl = curl.new()
	end
	local ret, data = Curl:download{ url = Url, ipv4 = true, A = "Mozilla/5.0 (Linux; Android 5.1.1; Nexus 4 Build/LMY48M)", followRedir = true, connectTimeout = timeout, o = output }
	if ret == CURL.OK then
		return data
	else
		return nil
	end
end

function init()
	-- set collectgarbage() interval from 200 (default) to 50
	collectgarbage('setpause', 50)

	categories = {};
	movies = {};
	n = neutrino();
	page = 1;
	max_page = 1;
	last_category_id = 1;
	selected_category_id = 0;
	selected_movie_id = 0;
	selected_stream_id = 0;
	mode = 0;
	config_file = "/var/tuxbox/config/netzkino.conf";
end

--Kategorien anzeigen
function get_categories()
	local h = hintbox.new{caption=caption, text="Kategorien werden geladen ...", icon=netzkino_png};
	h:paint();

	local data_cat = getdata(base_url .. "index.json?d=www")

	if data_cat then
		local j_table = json:decode(data_cat)
		local j_categories = j_table.categories
		local j = 1;
		for i = 1, #j_categories do
			local cat = j_categories[i];
			if cat ~= nil then
				-- Kategorie 9  -> keine Streams
				-- todo remove Kategorie 6481 & 6491(altes Glueckskino & Glueckskino) -> keine Streams
				if cat.id ~= 9 then
					categories[j] =
					{
						id           = j;
						category_id = cat.id;
						title        = cat.title;
						post_count   = cat.post_count;
					};
					j = j + 1;
				end
			end
		end
		h:hide();

		page = 1;
		if j > 1 then
			get_categories_menu();
		else
			messagebox.exec{title="Fehler", text="Keinen Kategorien gefunden!", icon="error", timeout=5, buttons={"ok"}}
		end
	else
		h:hide()
		messagebox.exec{title="Fehler", text="Fehler beim Öffnen der Kategorien!", icon="error", timeout=5, buttons={"ok"}}
	end
end

-- Erstellen des Kategorien-Menü
function get_categories_menu()
	selected_category_id = 0;
	m_categories = menu.new{name="" .. caption .. " Kategorien", icon=netzkino_png};

	m_categories:addKey{directkey=RC["home"], id="home", action="key_home"}
	m_categories:addKey{directkey=RC["setup"], id="setup", action="key_setup"}
	m_categories:addItem{type="separator"};

	for index, category_detail in pairs(categories) do
		local count = "(" .. category_detail.post_count .. ")"
		m_categories:addItem{type="forwarder", value=count, action="set_category", id=index, name=category_detail.title};
	end
	m_categories:exec()
	-- Alle Menüs verlassen
	if ret == MENU_RETURN["EXIT_ALL"] then
		return ret
	elseif tonumber(selected_category_id) ~= 0 then
		get_movies(selected_category_id);
	end
end

-- Setzen der ausgewählten Kategorie
function set_category(_id)
	selected_category_id = tonumber(_id);
	return MENU_RETURN["EXIT_ALL"];
end

-- Filme zur Kategorie laden (variabel Pro Seite)
function get_movies(_id)
	local index = tonumber(_id);
	local page_nr = tonumber(page);
	movies = {};

	last_category_id = index;

	local sh = n:FontHeight(FONT.MENU)
	local items = math.floor(580/sh - 4);
	if items > 10 then
		items = 10 -- because of 10 hotkeys
	end

	local h = hintbox.new{caption=caption, text="Kategorie wird geladen ...", icon=netzkino_png};
	h:paint();

	local data_movies = getdata(base_url .. "categories/" .. categories[index].category_id .. ".json?d=www" .. "&count=" .. items .. "d&page=" .. page_nr .. "&custom_fields=Streaming")

	if data_movies then
		local j_table = json:decode(data_movies)
		max_page = tonumber(j_table.pages);
		local posts = j_table.posts

		j = 1;
		for i = 1, #posts do
			local j_streaming = nil;
			local custom_fields = posts[i].custom_fields
			if custom_fields ~= nil then
				local stream = custom_fields.Streaming
				if stream ~= nil then
					j_streaming = stream[1]
				end
			end

			if j_streaming ~= nil then
				j_title = posts[i].title
				j_content = posts[i].content

				local j_cover="";
				local thumbnail = posts[i].thumbnail
				if thumbnail then
					j_cover = thumbnail
				end

				movies[j] =
				{
					id      = j;
					title   = j_title;
					content = j_content;
					cover   = j_cover;
					stream  = j_streaming;
				};
				j = j + 1;
			end
		end
		h:hide();

		if j > 1 then
			get_movies_menu(index);
		else
			messagebox.exec{title="Fehler", text="Keinen Stream gefunden!", icon="error", timeout=5, buttons={"ok"}}
			get_categories();
		end
	else
		h:hide()
		messagebox.exec{title="Fehler", text="Fehler beim Öffnen der Kategorie!", icon="error", timeout=5, buttons={"ok"}}
	end
end

--Auswahlmenü der Filme anzeigen
function get_movies_menu(_id)
	local index = tonumber(_id);
	local menu_title = caption .. ": " .. categories[index].title;
	selected_movie_id = 0;

	m_movies = menu.new{name=menu_title, icon=netzkino_png};

	m_movies:addKey{directkey=RC["home"], id="home", action="key_home"}
	m_movies:addKey{directkey=RC["setup"], id="setup", action="key_setup"}

	if max_page > 1 then
		local aktPage = tostring(page);
		local maxPage = tostring(max_page);
		local sText = "Seite " .. aktPage .. " von " .. maxPage
		m_movies:addItem{type="subhead", name=sText};
	end
	if page < max_page or page > 1 then
		m_movies:addItem{type="separator"};
	end
	if page < max_page then
		m_movies:addItem{type="forwarder", name="Nächste Seite", action="set_movie", id="-2", icon="blau", directkey=RC["blue"]};
		m_movies:addKey{directkey=RC["page_down"], action="set_movie", id="-2"}
		m_movies:addKey{directkey=RC["right"], action="set_movie", id="-2"}
	end
	if page > 1 then
		m_movies:addItem{type="forwarder", name="Vorherige Seite", action="set_movie", id="-1", icon="gelb", directkey=RC["yellow"]};
		m_movies:addKey{directkey=RC["page_up"], action="set_movie", id="-1"}
		m_movies:addKey{directkey=RC["left"], action="set_movie", id="-1"}
	end
	if page < max_page or page > 1 then
		m_movies:addItem{type="separatorline"};
	end
	m_movies:addItem{type="separator"};

	local d = 0 -- directkey
	local _icon = ""
	local _directkey = ""
	for index, movie_detail in pairs(movies) do
		if d < 10 then
			_icon = d
			_directkey = RC["".. d ..""]
		else
			-- reset
			_icon = ""
			_directkey = ""
		end
		m_movies:addItem{type="forwarder", action="set_movie", id=index, name=conv_utf8(movie_detail.title), icon=_icon, directkey=_directkey };
		d = d + 1
	end
	m_movies:exec()

	-- Alle Menüs verlassen
	if ret == MENU_RETURN["EXIT_ALL"] then
		return ret
	-- Zurück zum Kategorien-Menü
	elseif selected_movie_id == 0 then
		get_categories();
	-- Vorherige Seite laden
	elseif selected_movie_id == -1 then
		page = page - 1;
		get_movies(last_category_id);
	-- Nächste Seite laden
	elseif selected_movie_id == -2 then
		page = page + 1;
		get_movies(last_category_id);
	-- Filminfo anzeigen
	else
		show_movie_info(selected_movie_id);
	end
end

--Setzen des ausgewählten Films
function set_movie(_id)
	selected_movie_id = tonumber(_id);
	return MENU_RETURN["EXIT_ALL"];
end

-- Filminfos anzeigen
function show_movie_info(_id)

	local index = tonumber(_id);
	selected_stream_id = 0;
	mode = 0;

	local spacer = 8;
	local x  = 150;
	local y  = 70;
	local dx = 1000;
	local dy = 600;
	local ct1_x = 240;

	local window_title = caption .. "* " .. movies[index].title;
	w = cwindow.new{x=x, y=y, dx=dx, dy=dy, title=conv_utf8(window_title), icon=netzkino_png, btnRed="Film abspielen", btnGreen="Film downloaden" };
	local tmp_h = w:headerHeight() + w:footerHeight();
	ct1 = ctext.new{parent=w, x=ct1_x, y=20, dx=dx-ct1_x-2, dy=dy-tmp_h-40, text=conv_utf8(movies[index].content), mode = "ALIGN_TOP | ALIGN_SCROLL | DECODE_HTML"};

	if movies[index].cover ~= nil then
		getPicture(conv_utf8(movies[index].cover));

		local pic_x =  20
		local pic_y =  35
		local pic_w = 190
		local pic_h = 260
		local tmp_w;
		tmp_w, tmp_h = n:GetSize("/tmp/netzkino_cover.jpg");
		if tmp_w < pic_w then
			pic_x = (ct1_x - tmp_w) / 2;
		else
			pic_x = (ct1_x - pic_w) / 2;
		end
		cpicture.new{parent=w, x=pic_x, y=pic_y, dx=pic_w, dy=pic_h, image="/tmp/netzkino_cover.jpg"}
	end

	w:paint();
	ret = getInput(index);
	w:hide();

	if ret == MENU_RETURN["EXIT_ALL"] then
		return ret
	elseif selected_stream_id == 0 then
		get_movies(last_category_id);
	elseif selected_stream_id ~= 0 and mode == 1 then
		stream_movie(selected_stream_id);
		collectgarbage();
		get_movies(last_category_id);
	elseif selected_stream_id ~= 0 and mode == 2 then
		download_stream(selected_stream_id);
		collectgarbage();
		get_movies(last_category_id)
	end
end

function get_timing_menu()
	local ret = 0

	local conf = io.open("/var/tuxbox/config/neutrino.conf", "r")
	if conf then
		for line in conf:lines() do
			local key, val = line:match("^([^=#]+)=([^\n]*)")
			if (key) then
				if key == "timing.menu" then
					if (val ~= nil) then
						ret = val;
					end
				end
			end
		end
		conf:close()
	end

	return ret
end

--auf Tasteneingaben reagieren
function getInput(_id)
	local index = tonumber(_id);
	local i = 0
	local d = 500 -- ms
	local t = (get_timing_menu() * 1000) / d
	if t == 0 then
		t = -1 -- no timeout
	end
	repeat
		i = i + 1
		msg, data = n:GetInput(d)
		if msg >= RC["0"] and msg <= RC.MaxRC then
			i = 0 -- reset timeout
		end
		-- Taste Rot startet Stream
		if (msg == RC['ok']) or (msg == RC['red']) then
			selected_stream_id = index;
			mode = 1;
			break;
		-- Taste Gruen startet Download
		elseif (msg == RC['green']) then
			selected_stream_id = index;
			mode = 2;
			break;
		elseif (msg == RC['up'] or msg == RC['page_up']) then
			ct1:scroll{dir="up"};
		elseif (msg == RC['down'] or msg == RC['page_down']) then
			ct1:scroll{dir="down"};
		end
	-- Taste Exit oder Menü beendet das Fenster
	until msg == RC['home'] or msg == RC['setup'] or i == t;

	if msg == RC['setup'] then
		return MENU_RETURN["EXIT_ALL"]
	end
end

--herunterladen des Bildes
function getPicture(_picture)
	local fname = "/tmp/netzkino_cover.jpg";
	getdata(_picture, fname)
end

--Stream starten
function stream_movie(_id)
	local index = tonumber(_id);
	local stream_name = conv_utf8(movies[index].stream);
	video = video.new()
	video:PlayFile(conv_utf8(movies[index].title), "https://pmd.netzkino-seite.netzkino.de/" .. stream_name ..".mp4");
end

--Stream downloaden
function download_stream(_id)

	local index = tonumber(_id);
	local stream_name = conv_utf8(movies[index].stream);

	local cf = io.open(config_file, "r")
	if cf then
		for line in cf:lines() do
			d_path = line:match("download_path=(.-);");
		end
		cf:close();
	else
		local nc = io.open("/var/tuxbox/config/neutrino.conf", "r")
		if nc then
			for l in nc:lines() do
				local key, val = l:match("^([^=#]+)=([^\n]*)")
				if (key) then
					if key == "network_nfs_recordingdir" then
						if (val == nil) then
							d_path ="/media/sda1/movies/";
						else
							d_path = val;
						end
					end
				end
			end
			nc:close()
		end
	end

	local movie_file = d_path .. "/" .. conv_utf8(movies[index].title) .. ".mp4" ;
	local inhalt = "Netzkino HD: Download " .. conv_utf8(movies[index].title) .. " - Bitte warten...";
	local info_text = ctext.new{x=30, y=20, dx=900, dy=10, text=inhalt};
	info_text:paint()

	local ret = getdata("https://pmd.netzkino-seite.netzkino.de/" .. stream_name .. ".mp4", movie_file, 86400)
	info_text:hide();
	local download_text = ctext.new{x=30, y=20, dx=900, dy=50};

	if ret ~= nil then
		download_text:setText{text="[OK] Der Stream wurde erfolgreich heruntergeladen. OK zum verlassen."};
	else
		download_text:setText{text="[ERROR] Unbekannter Zustand oder Fehler. Versuche Mirror Server.\n" .. inhalt};
		download_text:paint();

		local ret = getdata("http://pmd.netzkino-and.netzkino.de/" .. stream_name .. ".mp4", movie_file, 86400)
		download_text:hide();
		if ret ~= nil then
			download_text:setText{text="[OK] Der Stream wurde erfolgreich heruntergeladen. OK zum verlassen."};
		else
			download_text:setText{text="[ERROR] Unbekannter Zustand oder Fehler. Bitte die Datei überprüfen. OK zum verlassen."};
		end
	end

	download_text:paint();

	repeat
		msg, data = n:GetInput(500)
	until msg == RC['home'] or msg == RC['setup'] or msg == RC['ok'];

	download_text:hide();
end

-- UTF8 in Umlaute wandeln
function conv_utf8(_string)
	if _string ~= nil then
		_string = string.gsub(_string,"\\u0026","&");
		_string = string.gsub(_string,"\\u00a0"," ");
		_string = string.gsub(_string,"\\u00b0","°");
		_string = string.gsub(_string,"\\u00b4","´");
		_string = string.gsub(_string,"\\u00c4","Ä");
		_string = string.gsub(_string,"\\u00d6","Ö");
		_string = string.gsub(_string,"\\u00dc","Ü");
		_string = string.gsub(_string,"\\u00df","ß");
		_string = string.gsub(_string,"\\u00e1","á");
		_string = string.gsub(_string,"\\u00e4","ä");
		_string = string.gsub(_string,"\\u00e8","è");
		_string = string.gsub(_string,"\\u00e9","é");
		_string = string.gsub(_string,"\\u00f3","ó");
		_string = string.gsub(_string,"\\u00f4","ô");
		_string = string.gsub(_string,"\\u00f6","ö");
		_string = string.gsub(_string,"\\u00f8","ø");
		_string = string.gsub(_string,"\\u00fb","û");
		_string = string.gsub(_string,"\\u00fc","ü");
		_string = string.gsub(_string,"\\u2013","–");
		_string = string.gsub(_string,"\\u2018","'");
		_string = string.gsub(_string,"\\u2019","'");
		_string = string.gsub(_string,"\\u201a","'");
		_string = string.gsub(_string,"\\u201b","'");
		_string = string.gsub(_string,"\\u201c","“");
		_string = string.gsub(_string,"\\u201d","\"");
		_string = string.gsub(_string,"\\u201e","„");
		_string = string.gsub(_string,"\\u201f","\"");
		_string = string.gsub(_string,"\\u2026","…");
		_string = string.gsub(_string,"&#038;","&");
		_string = string.gsub(_string,"&#039;","'");
		_string = string.gsub(_string,"&#8211;","–");
		_string = string.gsub(_string,"&#8212;","—");
		_string = string.gsub(_string,"&#8216;","‘");
		_string = string.gsub(_string,"&#8217;","’");
		_string = string.gsub(_string,"&#8230;","…");
		_string = string.gsub(_string,"&#8243;","″");
		_string = string.gsub(_string,"&amp;","&");
		_string = string.gsub(_string,"<[^>]*>","");
		_string = string.gsub(_string,"\\/","/");
		_string = string.gsub(_string,"\\n","");
	end
	return _string
end

--Main
init();
get_categories();
os.execute("rm /tmp/netzkino_*.*");
collectgarbage();
