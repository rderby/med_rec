module EncWin
using Gtk
#using GtkBuilder
#using Serialization
#using ReportParser
using Gtk.ShortNames   #, GtkReactive
#using GtkReactive
#include("../parser.jl")
using ..ReportParser
#
# b = GtkBuilder(filename="mygladewin.glade")
# win = b["window1"]
# showall(win)
ok, PtNames = ReportParser.deserialize_file("./data/MedRec_Pt_Encounter.idx")
println(" gtwin loaded PtNames ", length(PtNames))
ok, PtEncs = ReportParser.deserialize_file("./data/MedRec_Encounter.idx")
RootDir = "/Users/rderby/Data/text/"
global CurrentPage = 0
global NoReportPages = 4
global Report = Any[]
global CurEncs = Array{ReportParser.Encounter,1}[]
println("Reporttype=",typeof(Report))
#ok,mrn = ReportParser.get_pt_encounters(PtMrns,"22930")
#println(" gtwin loaded Mrns ", ok, " : ", length(PtMrns), PtMrns)
# for enc in PtMrns
#   println(enc)
# end

# tb = GtkTextBuffer
# get_gtk_property(tb, :text, String)
# tb.text(tb, "test", -1)
#
# tb.text[String] = "my text"

# b = GtkBuilder(filename= "pt_report.glade")
# tb = GtkTextBuffer
#
# mainBox = G_.object(b, "tv_report")
#
# buff = mainBox.buffer
# println("buff=",typeof(buff))


# w = b["rep_win"]
# showall(w)

function setindex()
end

function get_encounters(mrn)
  println("in getenccounters ",mrn, "length mrns ", length(PtEncs))
  found, encounters = ReportParser.get_pt_encounters(PtEncs, mrn)
  #println("found encounters ", encounters)
  return found, encounters
end

function load_encounter_list(mrn)
  #println("in load_enncs ",mrn)
  found,  encounters = get_encounters(mrn)
  println("found encounters ", found, "  ", encounters)

  if found
    #println("no encounter=", length(encounters))
    # first insert separator
    insert!(lsencs, 1, ("------------------", string("0")))
    for enc in reverse(encounters)
      insert!(lsencs, 1, (enc.report_path, enc.dos))
    end
  else
    println("Enounter Not Found with ", mrn)
  end
  println("returning: ", lsencs)
  return encounters
end

function getnames(search_key::String)
  #println("In get names ", length(PtNames), "search key ", search_key)
  found, names = ReportParser.find_names(PtNames, search_key)
  #println("found names ", names)
  return found, names
end
function load_pt_list(search_key)


  found, names = getnames(uppercase(search_key))
  println("names has ",names)

  if found
    insert!(lspts, 1, ("------------------","------------"))

    for choice in reverse(names)
      parts = split(choice, ':')
      name = strip(string(parts[1]))
      mrn = strip(string(parts[2]))
      insert!(lspts, 1, (name,mrn))
    end
  else
    println("Not Found  ", search_key)
  end
end

#function dowin()
  win = GtkWindow("A new window", 800, 400)

  g = GtkGrid()

  #regex entry for patient search
  ptregex = GtkEntry()
  set_gtk_property!(ptregex, :text, "D")


  #label for regex entry
  lbl = GtkLabel("Patient Name: ")

  # ptregex = GtkEntry()
  # set_gtk_property!(ptregex, :text, "^D")

  #Find patient button
  ptbtn = GtkButton("Find Patient")
  # function on_button_clicked(w)
  #   println("ptbtn button has been clicked")
  # end
  signal_connect(ptbtn, "clicked") do w
    #println(" was clicked again!")
    #empty!(lspts)
    txt = get_gtk_property(ptregex, :text, String)
    println("before load pt list")
    load_pt_list(txt)
  end

  #Patient selection list
  lspts = GtkListStore(String, String)
  tvpts = GtkTreeView(GtkTreeModel(lspts))

  rTxt = GtkCellRendererText()
  #rTog = GtkCellRendererToggle()
  c1 = GtkTreeViewColumn("Name", rTxt, Dict([("text", 0)]))
  c2 = GtkTreeViewColumn("MRN", rTxt, Dict([("text", 1)]))
  #c3 = GtkTreeViewColumn("Active", rTxt, Dict([("text",2)]))

  #tmFiltered = GtkTreeModelFilter(lspts)
  #GAccessor.visible_column(tmFiltered,2)
  #tvpts = GtkTreeView(GtkTreeModel(tmFiltered))

  push!(tvpts, c1, c2)
  for c in [c1, c2]
    GAccessor.resizable(c, true)
  end


  select_tvpts = GAccessor.selection(tvpts)
  signal_connect(select_tvpts, "changed") do widget

    if hasselection(select_tvpts)
      println("entry changed")
      currentIt = selected(select_tvpts)

      # println("Name: ", GtkTreeModel(tmFiltered)[currentIt,1],
      #       " Age: ", GtkTreeModel(tmFiltered)[currentIt,1])

      #search_key =   GtkTreeModel(tmFiltered)[currentIt,2]

      #println("search ", search_key)
      search_str = lspts[currentIt,2]
      global CurEncs = load_encounter_list(search_str)
      println("return from encounter search")

    end
  end

  #Selected patient Encounter List
  lsencs = GtkListStoreLeaf(String, String)
  tvencs = GtkTreeViewLeaf(GtkTreeModel(lsencs))
  rTxt = GtkCellRendererText()
  c11 = GtkTreeViewColumn("Encounters", rTxt, Dict([("text", 0)]))
  c22 = GtkTreeViewColumn("Date", rTxt, Dict([("text", 1)]))
  push!(tvencs, c11, c22)
  for c in [c11, c22]
    GAccessor.resizable(c, true)
  end
  select_encs = GAccessor.selection(tvencs)
  signal_connect(select_encs, "changed") do widget
    println("in select_encs")
    if hasselection(select_encs)
      #empty!(lbl_report)
      currentIt = selected(select_encs)
      # now you can to something with the selected item
      println("Encounter: ", lsencs[currentIt, 1])
      unique_file_path = lsencs[currentIt, 1]
      file_path = RootDir * unique_file_path
      global Report = ReportParser.load_report(file_path, NoReportPages)
      bff.text[String] = Report[1]
      global CurrentPage = 1

      # now load image list
    end
  end

  #Selected encounter Image List
  lsimg = GtkListStoreLeaf(String, String)
  tvimg = GtkTreeViewLeaf(GtkTreeModel(lsimg))
  rTxt = GtkCellRendererText()
  c11 = GtkTreeViewColumn("Fluro Image", rTxt, Dict([("text", 0)]))
  c22 = GtkTreeViewColumn("Date", rTxt, Dict([("text", 1)]))
  push!(tvimg, c11, c22)
  for c in [c11, c22]
    GAccessor.resizable(c, true)
  end
  select_image = GAccessor.selection(tvimg)
  signal_connect(select_image, "changed") do widget
    println("in select_image")
    if hasselection(select_image)
      # #empty!(lbl_report)
      # currentIt = selected(select_encs)
      # # now you can to something with the selected item
      # println("Encounter: ", lsencs[currentIt, 1])
      # unique_file_path = lsencs[currentIt, 1]
      # file_path = RootDir * unique_file_path
      # global Report = ReportParser.load_report(file_path, NoReportPages)
      # bff.text[String] = Report[1]
      # global CurrentPage = 1
    end
  end

  #Page Forward-Backward
  nxt_page_btn = GtkButton("->")
  signal_connect(nxt_page_btn, "clicked") do w
    println("typeof report",typeof(Report), "length=", length(Report))
    println("in nxt page")
    println("current page ", CurrentPage)

    if CurrentPage == NoReportPages
      global CurrentPage = 1
    else
      global CurrentPage += 1
    end
    println("CurrentPage ", CurrentPage)

    #println(report[current_page])
    #GAccessor.text(lbl_report, Report[2])
    global bff.text[String] = Report[CurrentPage]
  end

  prev_page_btn = GtkButton("<--")
  signal_connect(prev_page_btn, "clicked") do w
    # println("typeof report",typeof(Report), "length=", length(Report))
    # println("in nxt page")
    # println("current page ", CurrentPage)

    if CurrentPage == 1
      global CurrentPage = NoReportPages
    else
      global CurrentPage -= 1
    end
    println("CurrentPage ", CurrentPage)

    #println(report[current_page])
    #GAccessor.text(lbl_report, Report[2])
    global bff.text[String] = Report[CurrentPage]
  end

  #label to show report
  # lbl_report = GtkLabel("Patient Report")
  # #set_gtk_property!(lbl_report, :text, "Patient Report")
  #
  # GAccessor.selectable(lbl_report, true)
  # GAccessor.line_wrap(lbl_report, true)


  global bff = Gtk.TextBuffer()
  txtv_report = Gtk.TextView(buffer = bff)
  #GAccessor.line_wrap(txtv_report, true)

  bff.text[String] = "Patient Encounter"


  #pt_fluro = GtkImageLeaf("./images/20160202_03486_IMAGE179.BMP")


  # Now let's place these graphical elements into the Grid:
  g[1, 1] = lbl
  g[2, 1] = ptregex
  g[3, 1] = ptbtn

  g[1:2, 2] = tvpts
  g[3:5, 2] = tvencs
  g[6,1] = nxt_page_btn
  g[7,1] = prev_page_btn
  #g[6:15, 2] = lbl_report
  #g[15:20,2] = pt_fluro
  g[6:15,2] = txtv_report
  g[15:20,1] = tvimg

  push!(win, g)
  showall(win)

end
