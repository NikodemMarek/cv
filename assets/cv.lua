-- Gives the plain markdown CV some structure for the latex and html writers:
--   * H1 + following paragraph  -> header band with contact icons
--   * #### Company (Role, Dates) -> entry with company / role / right-aligned dates
--   * Skills list                -> label / value rows (chips in html)
--   * "... (2019 - 2024)" items  -> text with right-aligned dates
-- Other formats (docx) are left untouched.

local latex = FORMAT:match('latex') ~= nil
local html = FORMAT:match('html') ~= nil

local stringify = pandoc.utils.stringify

local function raw(s)
  return pandoc.RawInline(latex and 'latex' or 'html', s)
end

local function dashes(s)
  return (s:gsub(' %- ', ' – '))
end

local function trim_inlines(inlines)
  while #inlines > 0 and (inlines[1].t == 'Space' or inlines[1].t == 'SoftBreak') do
    inlines:remove(1)
  end
  while #inlines > 0 and (inlines[#inlines].t == 'Space' or inlines[#inlines].t == 'SoftBreak') do
    inlines:remove(#inlines)
  end
  return inlines
end

-- contact line ---------------------------------------------------------------

local svg = {
  email = '<path d="M4 4h16c1.1 0 2 .9 2 2v12c0 1.1-.9 2-2 2H4c-1.1 0-2-.9-2-2V6c0-1.1.9-2 2-2z"/><polyline points="22,6 12,13 2,6"/>',
  phone = '<path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7A2 2 0 0 1 22 16.92z"/>',
  location = '<path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"/><circle cx="12" cy="10" r="3"/>',
  linkedin = '<path d="M16 8a6 6 0 0 1 6 6v7h-4v-7a2 2 0 0 0-2-2 2 2 0 0 0-2 2v7h-4v-7a6 6 0 0 1 6-6z"/><rect x="2" y="9" width="4" height="12"/><circle cx="4" cy="4" r="2"/>',
  github = '<path d="M9 19c-5 1.5-5-2.5-7-3m14 6v-3.87a3.37 3.37 0 0 0-.94-2.61c3.14-.35 6.44-1.54 6.44-7A5.44 5.44 0 0 0 20 4.77 5.07 5.07 0 0 0 19.91 1S18.73.65 16 2.48a13.38 13.38 0 0 0-7 0C6.27.65 5.09 1 5.09 1A5.07 5.07 0 0 0 5 4.77a5.44 5.44 0 0 0-1.5 3.78c0 5.42 3.3 6.61 6.44 7A3.37 3.37 0 0 0 9 18.13V22"/>',
}

local fa = {
  email = '\\faEnvelope',
  phone = '\\faPhone',
  location = '\\faMapMarker*',
  linkedin = '\\faLinkedin',
  github = '\\faGithub',
}

local function classify(text)
  if text:match('@') then return 'email' end
  if text:match('^%+?[%d%s]+$') then return 'phone' end
  if text:lower():match('linkedin') then return 'linkedin' end
  if text:lower():match('github') then return 'github' end
  return 'location'
end

local function contact_items(para)
  local items, cur = {}, pandoc.Inlines{}
  local function flush()
    trim_inlines(cur)
    if #cur > 0 then items[#items + 1] = cur end
    cur = pandoc.Inlines{}
  end
  for _, el in ipairs(para.content) do
    if el.t == 'LineBreak' or (el.t == 'Str' and el.text == '•') then
      flush()
    else
      cur:insert(el)
    end
  end
  flush()

  -- make email and phone clickable
  for i, item in ipairs(items) do
    local text = stringify(item)
    local kind = classify(text)
    if kind == 'email' and item[1].t ~= 'Link' then
      items[i] = pandoc.Inlines{ pandoc.Link(text, 'mailto:' .. text) }
    elseif kind == 'phone' then
      items[i] = pandoc.Inlines{ pandoc.Link(text, 'tel:' .. text:gsub('%s', '')) }
    end
    items[i].kind = kind
  end
  return items
end

local function header_block(h1, para)
  local items = contact_items(para)
  if latex then
    local out = pandoc.Inlines{ raw('\\cvname{'), table.unpack(h1.content) }
    out:insert(raw('}\n\\begin{cvcontact}'))
    for i, item in ipairs(items) do
      if i > 1 then out:insert(raw('\\cvsep ')) end
      out:insert(raw('\\cvitem{' .. fa[item.kind] .. '}{'))
      out:extend(item)
      out:insert(raw('}'))
    end
    out:insert(raw('\\end{cvcontact}'))
    return { pandoc.Plain(out) }
  end

  local contact = pandoc.Inlines{}
  for _, item in ipairs(items) do
    local icon = raw('<svg class="icon" viewBox="0 0 24 24" aria-hidden="true">' .. svg[item.kind] .. '</svg>')
    contact:insert(pandoc.Span({ icon, table.unpack(item) }, { class = 'contact-item' }))
  end
  return {
    pandoc.Div({ h1, pandoc.Div(pandoc.Plain(contact), { class = 'contact' }) }, { class = 'cv-header' }),
  }
end

-- experience entries ---------------------------------------------------------

local function parse_entry(text)
  local company, inner = text:match('^(.-)%s*%((.*)%)%s*$')
  if not company then return nil end
  local role, dates = inner:match('^(.*),%s*(.-)$')
  if not role then return nil end
  return company, role, dashes(dates)
end

local function entry_head(h4)
  local company, role, dates = parse_entry(stringify(h4))
  if not company then return nil end
  if latex then
    return pandoc.Plain{
      raw('\\cventry{'), pandoc.Str(company), raw('}{'), pandoc.Str(role),
      raw('}{'), pandoc.Str(dates), raw('}'),
    }
  end
  h4.content = {
    pandoc.Span(company, { class = 'company' }),
    pandoc.Span(role, { class = 'role' }),
    pandoc.Span(dates, { class = 'dates' }),
  }
  return h4
end

-- skills ---------------------------------------------------------------------

local function skills_block(list)
  local rows = {}
  for _, item in ipairs(list.content) do
    local plain = item[1]
    if #item ~= 1 or not plain.content or plain.content[1].t ~= 'Strong' then return nil end
    local label = stringify(plain.content[1]):gsub(':%s*$', '')
    local rest = pandoc.Inlines{ table.unpack(plain.content, 2) }
    rows[#rows + 1] = { label = label, value = stringify(trim_inlines(rest)) }
  end

  if latex then
    local out = pandoc.Inlines{ raw('\\begin{cvskills}') }
    for _, row in ipairs(rows) do
      out:extend{ raw('\\cvskill{'), pandoc.Str(row.label), raw('}{'), pandoc.Str(row.value), raw('}') }
    end
    out:insert(raw('\\end{cvskills}'))
    return pandoc.Plain(out)
  end

  local blocks = {}
  for _, row in ipairs(rows) do
    local chips = pandoc.Inlines{}
    for chip in row.value:gmatch('[^,]+') do
      chip = chip:gsub('^%s+', ''):gsub('%s+$', '')
      chips:insert(pandoc.Span(dashes(chip), { class = 'chip' }))
    end
    blocks[#blocks + 1] = pandoc.Div({
      pandoc.Div(pandoc.Plain(row.label), { class = 'skill-label' }),
      pandoc.Div(pandoc.Plain(chips), { class = 'chips' }),
    }, { class = 'skill-row' })
  end
  return pandoc.Div(blocks, { class = 'skills' })
end

-- list items ending with "(2019 - 2024)" -------------------------------------

local function dated_list(list)
  local changed = false
  for _, item in ipairs(list.content) do
    local plain = item[1]
    if #item == 1 and plain.content then
      local text = stringify(plain)
      local body, dates = text:match('^(.-)%s*%((%d%d%d%d[^)]*)%)%s*$')
      if body then
        changed = true
        if latex then
          plain.content = { pandoc.Str(body), raw('\\cvdate{'), pandoc.Str(dashes(dates)), raw('}') }
        else
          plain.content = { pandoc.Span(body), pandoc.Span(dashes(dates), { class = 'dates' }) }
        end
      end
    end
  end
  if changed and html then
    return pandoc.Div(list, { class = 'dated' })
  end
  return list
end

-- document -------------------------------------------------------------------

function Pandoc(doc)
  if not (latex or html) then return doc end

  local out, section = pandoc.Blocks{}, nil
  local blocks = doc.blocks
  local i = 1
  while i <= #blocks do
    local b = blocks[i]
    if b.t == 'Header' and b.level == 1 and blocks[i + 1] and blocks[i + 1].t == 'Para' then
      out:extend(header_block(b, blocks[i + 1]))
      if html and doc.meta.pagetitle == nil then
        doc.meta.pagetitle = stringify(b)
      end
      i = i + 2
    else
      if b.t == 'Header' and b.level == 2 then
        section = stringify(b):lower()
        out:insert(b)
      elseif b.t == 'Header' and b.level == 4 then
        local head = entry_head(b)
        if head and html and blocks[i + 1] and blocks[i + 1].t == 'BulletList' then
          out:insert(pandoc.Div({ head, blocks[i + 1] }, { class = 'entry' }))
          i = i + 1
        else
          out:insert(head or b)
        end
      elseif b.t == 'BulletList' and section == 'skills' then
        out:insert(skills_block(b) or b)
      elseif b.t == 'BulletList' then
        out:insert(dated_list(b))
      else
        out:insert(b)
      end
      i = i + 1
    end
  end
  doc.blocks = out
  return doc
end
