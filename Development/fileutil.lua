FileUtil = {}

--[[ Note:
     
     fileHash and forEachFile will probably need replacements for other operating systems. ]]

--[[ Warning:
     
     Pretty much all these functions can be made to do something malicious if given bad file names;
     don't use input from untrusted sources. ]]

-- Our horrible test to check if you're using Windows or not.
local is_windows = os.getenv("HOMEDRIVE") ~= nil or
                   os.getenv("WINDIR") ~= nil or
                   os.getenv("OS") == "Windows_NT"

local home = os.getenv("HOME")

FileUtil.fileName = function(filename)
  local home_path = select(3, string.find(filename, "^~(.*)$"))
  
  if home_path then
    return (is_windows and (os.getenv("HOMEDRIVE")..os.getenv("HOMEPATH")) or os.getenv("HOME"))..home_path
  end
  
  return filename
end


FileUtil.quoteFileWindows = function (filename)
  -- Escapes filenames in Windows, and converts slashes to backslashes.
  
  filename = FileUtil.fileName(filename)
  
  if filename == "" then return "\"\"" end
  
  local result = ""
  for i=1,string.len(filename) do
    local c = string.sub(filename, i, i)
    if c == "/" then
      c = "\\"
    elseif string.find(c, "[^\\%.%a%d]") then
      c = "^"..c
    end
    
    result = result .. c
  end
  return result
end

FileUtil.quoteFileNix = function (filename)
  -- Escapes filenames in *nix, and converts backslashes  to slashes.
  -- Also used directly for URLs, which are always *nix style paths
  
  filename = FileUtil.fileName(filename)
  
  if filename == "" then return "\"\"" end
  
  local result = ""
  for i=1,string.len(filename) do
    local c = string.sub(filename, i, i)
    if c == "\\" then
      c = "/"
    elseif string.find(c, "[^/%.%-%a%d]") then
      c = "\\"..c
    end
    
    result = result .. c
  end
  
  return result
end

FileUtil.quoteFile = is_windows and FileUtil.quoteFileWindows or FileUtil.quoteFileNix

local function escapeForPattern(text)
  return string.gsub(text, "[%%%^%$%.%+%*%-%?%[%]]", function (x) return "%"..x end)
end

FileUtil.fileHash = function(filename)
  print(string.format("Hashing " .. filename))
  local stream = io.popen(string.format("sha1sum %s", FileUtil.quoteFile(filename)))
  
  if not stream then
    print("Failed to calculate hash: "..filename)
    return nil
  end
  
  local line = stream:read()
  io.close(stream)
  if line then
    return select(3, string.find(line, string.format("^([abcdef%%d]+)  %s$", escapeForPattern(filename))))
  end
end

FileUtil.fileExists = function(filename)
  local stream = io.open(FileUtil.fileName(filename), "r")
  if stream then
    io.close(stream)
    return true
  end
  return false
end

FileUtil.isDirectory = function(filename)
  local stream = io.popen(string.format(is_windows and "DIR /B /AD %s" or "file -b %s", FileUtil.quoteFile(filename)), "r")
  if stream then
    local result = stream:read("*line")
    io.close(stream)
    return is_windows and (result ~= "File Not Found") or (result == "directory")
  end
  error("Failed to execute 'file' command.")
end

-- Extra strings passed to copyFile are pattern/replacement pairs, applied to
-- each line of the file being copied.
FileUtil.copyFile = function(in_name, out_name, ...)
  local extra = select("#", ...)
  
  if FileUtil.isDirectory(out_name) then
    -- If out_name is a directory, change it to a filename.
    out_name = string.format("%s/%s", out_name, select(3, string.find(in_name, "([^/\\]*)$")))
  end
  
  if extra > 0 then
    assert(extra%2==0, "Odd number of arguments.")
    local src = io.open(in_name, "rb")
    if src then
      local dest = io.open(out_name, "wb")
      if dest then
        while true do
          local original = src:read("*line")
          if not original then break end
          local eol
          original, eol = select(3, string.find(original, "^(.-)(\r?)$")) -- Try to keep the CR in CRLF codes intact.
          local replacement = original
          for i = 1,extra,2 do
            local a, b = select(i, ...)
            replacement = string.gsub(replacement, a, b)
          end
          
          -- If we make a line blank, and it wasn't blank before, we omit the line.
          if original == replacement or replacement ~= "" then
            dest:write(replacement, eol, "\n")
          end
        end
        io.close(dest)
      else
        print("Failed to copy "..in_name.." to "..out_name.."; couldn't open "..out_name)
      end
      io.close(src)
    else
      print("Failed to copy "..in_name.." to "..out_name.."; couldn't open "..in_name)
    end
  else
    local f = assert(io.open(in_name, "rb"))
    local d = f:read("*all")
    f:close()
    f = assert(io.open(out_name, "wb"))
    f:write(d)
    f:close()
  end
end

FileUtil.forEachFile = function(directory, func)
  if directory == "" then
    directory = "."
  end
  
  local stream = io.popen(string.format(is_windows and "DIR /B %s" or "ls -1 %s", FileUtil.quoteFile(directory)))
  
  if not stream then
    print("Failed to read directory contents: "..directory)
    return
  end
  
  while true do
    local filename = stream:read()
    if not filename then break end
    filename = directory.."/"..filename
    
    if FileUtil.fileExists(filename) then
      func(filename)
    end
  end
  
  io.close(stream)
end

FileUtil.copyDirectoryRecursively = function(src, dest)
  if os.execute(string.format("cp -r %s %s", src, dest)) ~= 0 then
    print(string.format("Failed to copy %s to %s", src, dest))
    assert(false)
  end
  
  os.execute(string.format("rm -rf %s/.*", dest))
end

FileUtil.extension = function(filename)
  local ext = select(3, string.find(filename, "%.([^%s/\\]-)$"))
  return ext and string.lower(ext) or ""
end

FileUtil.updateSVNRepo = function(url, directory)
  -- Check for the SVN entries file, which should exist regardless of OS; fileExists doesn't work for directories under Windows.
  if FileUtil.fileExists(directory.."/.svn/entries") then
    if os.execute(string.format("svn up -q %s", FileUtil.quoteFile(directory))) ~= 0 then
      print("Failed to update svn repository: "..directory.." ("..url..")")
    end
  else
    -- quoteFile on Windows results in invalid URLs, so just wrap it in quotes and be done with it
    if os.execute(string.format("svn co -q %s %s", is_windows and "\""..url.."\"" or FileUtil.quoteFile(url), FileUtil.quoteFile(directory))) ~= 0 then
      print("Failed to up fetch svn repository: "..directory.." ("..url..")")
    end
  end
end

FileUtil.createDirectory = function(directory)
  if os.execute(string.format(is_windows and "MD %s" or "mkdir -p %s", FileUtil.quoteFile(directory))) ~= 0 then
    print("Failed to create directory: "..directory)
    print(string.format(is_windows and "MD %s" or "mkdir -p %s", FileUtil.quoteFile(directory)))
    os.execute("pwd")
    os.exit(1)
  end
end

FileUtil.unlinkDirectory = function(directory)
  if os.execute(string.format(is_windows and "RMDIR /S /Q %s" or "rm -rf %s", FileUtil.quoteFile(directory))) ~= 0 then
    print("Failed to unlink directory: "..directory)
  end
end

FileUtil.unlinkFile = function(file)
  if not os.remove(file) then
     print("Couldn't remove file " .. file)
  end
end

FileUtil.convertImage = function(source, dest)
  if source ~= dest then
    if FileUtil.extension(source) == "svg" then
      -- Because convert doesn't properly render SVG files,
      -- I'm going to instead use rsvg to render them to some temporary location,
      -- and then use convert on the temporary file.
      local temp = os.tmpname()..".png"
      print(string.format("rsvg -fpng %s %s", FileUtil.quoteFile(source), FileUtil.quoteFile(temp)))
      if os.execute(string.format("rsvg -fpng %s %s", FileUtil.quoteFile(source), FileUtil.quoteFile(temp))) ~= 0 then
        print("Failed to convert: "..source)
        print(tostring(os.execute(string.format("rsvg -fpng %s %s", FileUtil.quoteFile(source), FileUtil.quoteFile(temp))) ~= 0))
        print(tostring(os.execute(string.format("rsvg -fpng %s %s", FileUtil.quoteFile(source), FileUtil.quoteFile(temp))) ~= 0))
        print(tostring(os.execute(string.format("rsvg -fpng Development/%s %s", FileUtil.quoteFile(source), FileUtil.quoteFile(temp))) ~= 0))
        print(tostring(os.execute(string.format("rsvg -fpng %s %s", FileUtil.quoteFile(source), FileUtil.quoteFile(temp))) ~= 0))
        os.execute("pwd")
        print("lulz")
        os.exit(1)
      else
        FileUtil.convertImage(temp, dest)
        FileUtil.unlinkFile(temp)
      end
    elseif os.execute(string.format("convert -background None %s %s", FileUtil.quoteFile(source), FileUtil.quoteFile(dest))) ~= 0 then
      print(string.format("convert -background None %s %s", FileUtil.quoteFile(source), FileUtil.quoteFile(dest)))
      print("Failed to convert: "..source)
      os.exit(1)
    end
  end
end

FileUtil.createZipArchive = function(directory, archive)
  if os.execute(string.format("zip -rq9 %s %s", FileUtil.quoteFile(archive), FileUtil.quoteFile(directory))) ~= 0 then
    print("Failed to create zip archive: "..archive)
  end
end

FileUtil.create7zArchive = function(directory, archive)
  if os.execute(string.format("7z a -t7z -m0=lzma -mx=9 -mfb=64 -md=32m -ms=on %s %s", FileUtil.quoteFile(archive), FileUtil.quoteFile(directory))) ~= 0 then
    print("Failed to create 7z archive: "..archive)
  end
end

FileUtil.fileContains = function(filename, text)
  local rv = os.execute(string.format("grep %s %s", text, filename))
  return rv == 0
end
