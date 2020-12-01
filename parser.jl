module ReportParser

using CBinding
using Printf
using Mmap
using Pipe
using Serialization
using Match
using TOML
using Match
using DataStructures
#include("VisualFoxPro.jl")
#using ..GtkWin

#string utilities
function parse_date(indate)
    # if not valid date then parse from filename
    #expect m/d/y format
    parts = split(indate,'/')
    # expect 3 parts
    mm=""
    dd=""
    yyyy=""
    if length(parts)==3
            if length(mm)==1
                mm = "0" * parts[1]
            else
                mm = parts[1]
            end
        dd = parts[2]
            if length(dd)==1
                dd = "0" * dd
            end
        yyyy = parts[3]
            if length(yyyy) == 2
                yyyy = "19" * yyyy
            end
        return yyyy * mm * dd
    end
    return ""
end

#Config
function load_configs(filepath)
    filepath = "./config/config.toml"
    configs = Dict()
    try
        configs = TOML.parsefile(filepath)
    catch err
        msg = @sprintf("unable to open %s due to %s", filepath, err)
        rethrow(err)
    end
    root = configs["root_dir_paths"]["report_source_dir"]
    println("report source dir: ", root)
    configs

end



export load_report
function load_report(file_path::String, noparts)
    #file_path = "/Users/rderby/Data/text/199701/AurJ012397.txt"
    reportfile = open(file_path)
    lines = readlines(reportfile)
    close(reportfile)
    report = Any[]
    println("lines=",length(lines))
    nolines = length(lines)

    linesperpart =  floor(nolines/noparts)
    println(typeof(linesperpart))
    println(linesperpart)

    modlines = Int(nolines - (linesperpart*noparts))
    println("mod=",modlines)
    for i = 1:noparts
        lip = 0
        lip = Int(linesperpart)
        if i == noparts
            lip +=  modlines
        end
        # println(lip)
        part = ""
        for l = 1:lip
            ln = Int((linesperpart*(i-1))) + l
            part =  part * lines[ln] * "\n"
        end
        push!(report,part)
    end
    report

end

function dict_add(dict,dict_key,value)

        if haskey(dict,dict_key) == false
            #the unique value is the unique file path
            values = Any[]
            push!(values,value)
            dict[dict_key] = values

        else
            values = dict[dict_key]
            push!(values,value)
            dict[dict_key] = values

        end
end

#config functions
# create a med_rec_keys dictionary from toml file
struct MedRecKey
    str_key
    base_key
    process_key
    required
end

# create a dictionary of MedRecKey from toml file
# meedreckeys = medical record keys = a list of report headers with alliases
#   that will be used when parsing medical reports (or any other document)
#   Header patterns in report are identified by  e.g. header_regex = r"[A-Z -#]+:"
#   and then when needed the more specific header e.g. MR#: or PATIENT NAME: can be
#   changed to a common base_idx using created medreckeys.idx
function create_medreckeys(filepath)
    #filepath valid
    data = Dict()
    mrk = Dict()
    mrk_base = Dict()
    try
        data = TOML.parsefile(filepath)
    catch err
        msg = @sprintf("unable to open %s due to %s", filepath, err)
        rethrow(err)
    end
    #now create dictionary
    #println(data["medreckeys"][1])
    for i = 1:length(data["medreckeys"])
        value_dict = Dict()
        value = data["medreckeys"][i] #println(data["medreckeys"][i])
        key = value["str_key"]
        for (k, v) in value
            value_dict[k] = v
        end
        #println(value_dict["str_key"])
        mrk[key] = value_dict
        dict_add(mrk_base, value_dict["base_key"], value_dict)
    end
    Serialization.serialize("data/medreckeys.idx", mrk)
    Serialization.serialize("data/medreckeys_base.idx", mrk_base)
    return mrk, mrk_base
end


@cstruct Data {
    @cunion {
        data::UInt8[102400]
        int_val::UInt
    }
}

#key value module
function get_values(keyvalues,key)
    for keyvalue in keyvalues
        if key==keyvalue.key
             return true,keyvalue.values
        end
    end
    return false,[""]
end


function get_alias_value(keyvalues,aliases,basekey)
    #println(aliases[basekey])

    for alias in aliases[basekey]

        found,alias_key_value = get_values(keyvalues,alias["str_key"])
        if found && length(alias_key_value) > 0
            #println("kvlen=",length(alias_key_value))
            return true,alias_key_value[1]
        end
    end
    return false,""
end

export Encounter
struct Encounter
    mrn::String
    report_path:: String
    pt_name::String  #last, first
    dos::String #yyyymmdd
    provider::String  #last, first
end

function load_enc_images(enc::Encounter)
    # unique name example 1999_12/19991201_14215_833.bmp

    # must have and dos and mrn
    # if enc.dos=="" || length(dos)<8 || env.mrn==""
    #     return false,""
    # end
    # dir = enc[dos][1:4] * "_" * enc[dos][5:6]
    # fn = dir * "/" * enc.dos * "_" * enc.mrn * "_"
end

function parse_out_encounter(keyvalues)

    #need MRN PT PP (primary provider) DOS
    found,mrn = get_values(keyvalues,"MRN")
    found,file_path = get_values(keyvalues,"FILE_PATH")
    found,raw_dos = get_values(keyvalues,"DOS")
    dos = ""
        if length(raw_dos) > 0
            dos = parse_date(raw_dos[1])
        end
    found,pt = get_values(keyvalues,"PT")
    found,pp = get_values(keyvalues,"PP")
    enc = Encounter(mrn[1],file_path[1],pt[1],dos,pp[1])
    return enc

end


function create_encs_by_ptname(enc_dict)
    pt_dict = SortedDict{String,String}()
    for enc in values(enc_dict)
        if length(enc) > 0 && length(enc[1].pt_name) > 0
            insert!(pt_dict, enc[1].pt_name, enc[1].mrn)
        end
    end
    return pt_dict
end

function get_pt_encounters(enc_dict::MultiDict{String,Encounter}, key::String)

    if haskey(enc_dict,key)
        return true,enc_dict[key]
    else
        return false,nothing
    end
end
function create_encounter_dictionary(records,aliases, basekeyname)
     encs= MultiDict{String,Encounter}()

    for keyvalues in records
        enc = parse_out_encounter(keyvalues)
        push!(encs,enc.mrn=>enc)
    end

    return encs
end

function create_dictionary(records,aliases, basekeyname)
    #aliases = Serialization.deserialize("data/medreckeys_base.idx")
    #dict  = Dict{String,Array{String}}
    dict = Dict()
    #println(aliases["MRN"])

    #println(typeof(records))
    for keyvalues in records
        # does keyvalues array contain key
        found,file_path = get_values(keyvalues,"FILE_PATH:")
        #println("filepath", file_path)
        if found
            found,key = get_alias_value(keyvalues,aliases,basekeyname)
            if found
                dict_add(dict,key,file_path[1])
            end
        end
    end
    return dict
end

function make_key(values,val_idxs)
    key = Any[]
    for idx in val_idxs
        if idx<=length(values)
            #value = value * "^" * values[idx]
            push!(key,values[idx])
        end
    end
    return key
end

export deserialize_file
function deserialize_file(file_path)
    try
        data = Serialization.deserialize(file_path)
        println("data has ",length(data))
        return true,data
    catch err
        msg = @sprintf("unable to deserialize %s due to %s", file_path, err)
        println(msg)
        return rethrow(err)
    end

end


function increment_last_letter(str::String)
    istr = ""
    for i = 1:length(str)
        c = str[i]
        if i == length(str)
            c+=1
        end
        istr = istr * c
    end
    istr
end

export find_names


function find_names(name_dict::SortedDict{String,String}, key::String)
    #increment last letter in key
    first = searchsortedfirst(name_dict,key)
    after_key =increment_last_letter(key)
    after  = searchsortedafter(name_dict,after_key)

    #pts = Array{String,1}[]
    pts = Any[]
    #println("")
    #println("patient=", first, " : ",after)
    for (k,v) in exclusive(name_dict,first,after)
        push!(pts,k * ": " * v)
    end
    println("in find_names: ", pts)
    found = length(pts)>0
    return found,pts
end

function find_names(ptnames,nm_regex)
    found_names = Any[]
    found_first=false
    matched=false
    #println("len ptnames=",length(ptnames))
    for (idx,name) in enumerate(ptnames)
        #print(name,":")
        matched = occursin(nm_regex,name)
        if matched
            push!(found_names,name)
            found_first=true
        elseif found_first && matched==false
            break
        end
    end
    #println(found_names)
    return found_first,found_names
end

export get_pt_encounters

function get_pt_encounters(mrndict::Dict{Any,Any}, mrnkey::String)
    println("in get_pt_encounters with mrnkey=",mrnkey)
    if haskey(mrndict,mrnkey)
        println("found mrn ", mrndict[mrnkey])
        return true,mrndict[mrnkey]
    else
        println("Not found: ", mrnkey)
        return false,Any("Not Found")
    end

end

function sorted_contains(sorted,value)
    for v in sorted
        if v==value
            return true
        end
    end
    return false
end
function create_sorted(records,key,val_idxs)
    sorted = Any[]
    dict  = Dict()
    #println(typeof(records))
    for keyvalues in records
        # does keyvalues array contain key
        found, values = get_values(keyvalues,key)
        if found
            found,mrn = get_values(keyvalues,"MRN")
            if found
                value = make_key(values,val_idxs)
                if length(value)>0 && !haskey(dict,value)
                        dict[value] = value[1]
                        value = value[1] * ": " * mrn[1]
                        push!(sorted,value)
                end#if
            end
        end#if
    end#for
    return sort(sorted)
end

mutable struct ReportHeaders
    key
    values
end

struct Report
    file_path:: String
    data_len::UInt32
    data
end

function load_report(file_path)
    file_size = filesize(file_path)
    data = open(file_path, "r+") do io
               Mmap.mmap(io, Vector{UInt8}, file_size) #sizeof(DB_header))
    end;
    #dat = unsafe_wrap(Data, pointer(data));
    Report(file_path,file_size,data)
end


function get_all_file_paths(root_dir,repdir_regex,filepath_regex)
    file_paths = Any[]
    #repdir_regex = r"([0-9][0-9][0-9][0-9][0-9][0-9])"
    foreach(readdir(root_dir)) do f
        sub_dir_path = root_dir * "/" * f
        unique_dir = f
        if isdir(sub_dir_path) && occursin(repdir_regex,sub_dir_path)
            foreach(readdir(sub_dir_path)) do f
                file_path = sub_dir_path * "/" * f
                if isfile(file_path) && occursin(filepath_regex,f)
                    unique_path = unique_dir * "/" * f
                    push!(file_paths,unique_path)
                end
            end
        end
    end
    return file_paths
end

#split the hdr value into array of lines
#delete lines with only white spaces
#delete : end of hdr
function parse_first_last_name(first_last_name)
    name = ""
    parts = split(first_last_name)
    len = length(parts)
     @match len  begin
        1 => begin;name = parts[1];end
        2 => begin;name =  parts[2] * ", " * parts[1];end
        3 => begin;name = parts[2] * ", " * parts[1] * " " * parts[3];end
    end
    return name
end


function clean_hdr_text(rep_hdr,txt)
    rep_hdr.values = values = Any[]
    strip_vals = [' ','\t','_']
    @pipe txt |>
    split(_,"\n") |>
    for (idx,value) in enumerate(_)
        if length(value) > 0; push!(values , strip(value,strip_vals)) ; end
    end
    #rep_hdr.key = strip(rep_hdr.key,':')
    #check if name
    if occursin("NAME",rep_hdr.key) && length(rep_hdr.values) >0
        rep_hdr.values[1] = parse_first_last_name(rep_hdr.values[1])
    end

end

function get_headers(file_path,report,aliases)
    header_regex = r"[A-Z -#]+:"
    page1 = r"PAGE 1"
    strip_vals = [' ','\t']
    offsets = Any[]
    hdrs = Any[]
    fp = Any[]

    push!(fp,file_path)
    push!(hdrs,ReportHeaders("FILE_PATH",fp))
    push!(offsets,0)

    for i in eachmatch( header_regex, report)
        push!(hdrs,ReportHeaders(strip(i.match,strip_vals),""))
        push!(offsets,i.offset)
    end
        #now get string between


    for (idx,hdr) in enumerate(hdrs)
        if idx>2
            ofs0 = offsets[idx-1]
            ofs1 = offsets[idx]

            txt = @pipe report[ofs0:ofs1] |>
            replace(_,hdrs[idx-1].key => "") |>
            replace(_,page1 => "") |>
            strip

            #hdrs[idx-1].values[1] = txt
            clean_hdr_text(hdrs[idx-1],txt)
            #println(hdrs[idx-1])
        end


     end

     # get aliases of MRN
     found,mrn = get_alias_value(hdrs,aliases,"MRN")
     if found
         push!(hdrs,ReportHeaders("MRN",Any[mrn]))
     end

     #date of service
     found,dos = get_alias_value(hdrs,aliases,"DOS")
     if found
         push!(hdrs,ReportHeaders("DOS",Any[dos]))
     end

     #primary provider (encounter provider )
     found,pp = get_alias_value(hdrs,aliases,"PP")
     if found
         push!(hdrs,ReportHeaders("PP",Any[pp]))
     end

     #patient name
     found,pt = get_alias_value(hdrs,aliases,"PT")
     if found
         push!(hdrs,ReportHeaders("PT",Any[pt]))
     end
     return hdrs
end

function parse_all_reports(root_dir,file_paths, aliases)
    records = Any[]
    no_searched = 0
    for (index, file_path_unique) in enumerate(file_paths)
        file_path = root_dir * "/" * file_path_unique
        report = load_report(file_path)
        no_searched += 1
        rd = String(report.data)
        push!(records,get_headers(file_path_unique,rd,aliases))
    end
    return no_searched,records
end

function search_files(root_dir, file_paths)
    no_searched = 0
    proc_regex = r"PROCEDURE:.*"
    mrn_regex = r"MR#.*"
    disco_regex = r"Discogram"
    matches = Any[]
    for (index, file_path_unique) in enumerate(file_paths)
        #foreach(readdir(file_path)) do f
        file_path = root_dir * "/" * file_path_unique

        report = load_report(file_path)
        no_searched += 1
        rd = String(report.data)
        m_proc = match(proc_regex, rd)

        if m_proc != nothing && occursin.(disco_regex, m_proc.match)
            #if occursin.(disco_regex,String(m_proc.match))
            #testing
            get_all_headers(rd)
            m_mrn = match(mrn_regex, rd)
            if m_mrn != nothing
                push!(
                    matches,
                    file_path_unique *
                    ": mrn: " *
                    m_mrn.match *
                    " procedure: " *
                    m_proc.match,
                )
            end
        end
    end
    return no_searched, matches
end

function parse_medical_reports()
    mrk_file_path = "config/parse_key.toml"
    mrk_base = Dict()
    mrk = Dict()

    try
        mrk,mrk_base = create_medreckeys(mrk_file_path)
    catch err
        return
        #throw(err)
    end

    root_dir = "/Users/rderby/Data/text"
    filepath_regex = r"\.[tT][xX][tT]$"
    #filepath_regex = r"zama122203.txt"
    repdir_regex = r"([0-9][0-9][0-9][0-9][0-9][0-9])"
    #repdir_regex = r"(200312)"

    file_paths = get_all_file_paths(root_dir,repdir_regex,filepath_regex)
    no_searched,records = parse_all_reports(root_dir,file_paths,mrk_base)
    println("parsed: ",no_searched)

    encounters = create_encounter_dictionary(records,mrk_base,"MRN")
    Serialization.serialize("data/MedRec_Encounter.idx", encounters)
    #println(encounters)

    pts = create_encs_by_ptname(encounters)
    Serialization.serialize("data/MedRec_Pt_Encounter.idx",pts)

    # nms = find_names(pts,"M")
    # println(nms)

    # e = get_pt_encounters(encounters,"22981")
    # println("found patient 22981: ",e)


    #create dictionary MR#'s'
    dict = create_dictionary(records,mrk_base,"MRN")
    Serialization.serialize("data/MedRec_MRN.idx", dict)

    #create sorted list patients
    names = create_sorted(records,"PATIENT NAME:",[1])
    Serialization.serialize("data/MedRec_PatientName.idx", names)

    return dict,names

end

export parse_medical_reports
#mrnidx = Dict()
#ptnames = Serialization.deserialize("./data/MedRec_PatientName.idx")


parse_medical_reports()
end #ReportParser
