module VisualFoxPro
using CBinding
using Printf
using Mmap

export display_fields
file_path = "/Users/rderby/Data/Medical/Data/bu_20201008/Stratford/302926/share/m6nmpv.dbf"


# pub struct DbFld {
#     name: String,          // 0->10 byes
#     fld_type: char,        //11
#     offset: usize,         // 12-15
#     len: usize,            //16
#     decimal_places: usize, //17
#     field_flags: u8,       //18
#     auto_inc_next: usize,  //19-22
#     auto_inc_step: usize,  //23
# }

@cstruct DbField {
    fld_name:: UInt8[11] # 11
    fld_type:: UInt8     # 1
    fld_offset:: UInt32  # 4
    fld_len:: UInt8      # 1
    decimal_places:: UInt8 # 1
    fld_flags:: UInt8      # 1
    auto_inc_next::UInt32  # 4
    auto_inc_step::UInt8   # 1
    reserved::UInt8[8]      # 8
}

struct FieldDescp
    #fld_name:: String
    fld_type::UInt8
    fld_offset::UInt32
    fld_len::UInt8
end

# // 0	DBF File type:
# // 0x02   FoxBASE
# // 0x03   FoxBASE+/Dbase III plus, no memo
# // 0x30   Visual FoxPro
# // 0x31   Visual FoxPro, autoincrement enabled
# // 0x32   Visual FoxPro with field type Varchar or Varbinary
# // 0x43   dBASE IV SQL table files, no memo
# // 0x63   dBASE IV SQL system files, no memo
# // 0x83   FoxBASE+/dBASE III PLUS, with memo
# // 0x8B   dBASE IV with memo
# // 0xCB   dBASE IV SQL table files, with memo
# // 0xF5   FoxPro 2.x (or earlier) with memo
# // 0xE5   HiPer-Six format with SMT memo file
# // 0xFB   FoxBASE
#
# // 1 - 3	Last update (YYMMDD)
# // 4 - 7	Number of records in file
# // 8 - 9	Position of first data record
#
# // 10 - 11	Length of one data record, including delete flag
# // 12 - 27	Reserved
# // 28	Table flags:
# // 0x01   file has a structural .cdx
# // 0x02   file has a Memo field
# // 0x04   file is a database (.dbc)
# // This byte can contain the sum of any of the above values. For example, the value 0x03 indicates the table has a structural .cdx and a Memo field.
# // 29	Code page mark
# // 30 - 31	Reserved, contains 0x00
# // 32 - n	Field subrecords
# // The number of fields determines the number of field subrecords. One field subrecord exists for each field in the table.
# // n+1	Header record terminator (0x0D)



@cstruct DbHeader      {      # struct DbHeader {
    db_type::UInt8                #   1
    last_update::UInt8[3]         #   3
    no_records::UInt32            #   4
    pos_first_record::UInt16      #   2
    record_length::UInt16         #   2
    reserved_1::UInt8[16]         #   16
    tbl_flags::UInt8              #   1
    page_mark::UInt8              #   1
    reserved_2::UInt8[2]          #   2
    field::DbField[10]
}


# @cstruct DbRecord {
#         str_val::UInt8[250]
# }
@cstruct DbRecord {
    @cunion {
        str_val::UInt8[250]
        int_val::UInt
    }
}

# utility functions

function u8_array_tostring(sa,len)
    s = ""
    for i in 1:len
        #println(sa[i])
        nc = @sprintf "%c" sa[i]
        if nc == "\0" || nc== ' '
            break
        end
        s = string(s, nc)
    end
    return strip(s)
end

function equal_str_values(u8_str,str,len)

    if str=="*"
        return true
    end

    if len != length(str) || len==0
        return false
    end
    for i = 1:len

        if  Int(str[i]) != u8_str[i]
            return false
        end
    end
    return true
end

function trim_spaces(a,len)
    while len > 0
        if a[len] != 32 || a[len]==0
            return len
        end
        len -= 1
    end
    return len
end

function load_foxpro(file_path)
    file_size = filesize(file_path)
    data = open(file_path, "r+") do io
               Mmap.mmap(io, Vector{UInt8}, file_size) #sizeof(DB_header))
           end;
    header = unsafe_wrap(DbHeader, pointer(data));
    FoxPro(file_path,data,header)
end

struct FoxPro
    file_path:: String
    data
    header:: DbHeader

end

function get_header_field(db,fld_idx)
    startidx = 33 + fld_idx*32
    if check_end(db,startidx)==true
        return nothing,true
    end
    fldptr = pointer(db.data[startidx:startidx+32])
    fld = unsafe_wrap(DbField, fldptr)
    return fld, false
end

# data_record functions
function get_data_record(db,rec_idx,offset)
    # add one to obtain julia base 1 array
    startidx = db.header.pos_first_record + 1 + ((rec_idx-1) * db.header.record_length) + offset
    # if check_end(db,startidx)==true
    #     return nothing,true
    # end
    #@printf "startidx=%d \n" startidx
    recptr = pointer(db.data[startidx:startidx+db.header.record_length])
    record = unsafe_wrap(DbRecord, recptr)
    return record, false
end
function get_data_record(db,rec_idx,fld)
    # add one to obtain julia base 1 array
    #pos = db.header.pos_first_record;
    #ofs = fld.fld_offset
    startidx = db.header.pos_first_record + 1 + (rec_idx * db.header.record_length) + fld.fld_offset
    # if check_end(db,startidx)==true
    #     return nothing,true
    # end
    #@printf "startidx=%d \n" startidx
    recptr = pointer(db.data[startidx:startidx+fld.fld_len])
    record = unsafe_wrap(DbRecord, recptr)
    return record, false
end
function get_record_value(db,rec_idx,fld_name)
    fld,found = get_field_by_name(db,fld_name)
    if found
        #@printf "fld offset: %d \n" fld.fld_offset
        value,ok = get_data_record(db,rec_idx,fld.fld_offset)
        return u8_array_tostring(value.str_val,fld.fld_len)
    end
    return ""
end
function get_record_value(db, rec_idx, fld)
    value, ok = get_data_record(db, rec_idx, fld)
    return value
    #return u8_array_tostring(value.str_val, fld.fld_len)
end

function select_record(db, start_idx,fld_name, match_val)
    matches = Any[]
    if start_idx>db.header.no_records
        return matches
    end
    #get fld
    fld, found = get_field_by_name(db,fld_name)
    if !found
        return matches
    end
    match_val_len = length(match_val)

    for i = start_idx:db.header.no_records-1
        value = get_record_value(db, i, fld)
        value_len = trim_spaces(value.str_val,fld.fld_len)

        if  match_val_len==value_len && equal_str_values(value.str_val,match_val,value_len)==true
            lname_str = u8_array_tostring(value.str_val, value_len)
            match = @sprintf "%d: %s" i lname_str
            push!(matches, match)
        end
    end
    return matches
end

function match_record(db, rec_idx, flds, match_vals)
    values = Any[]
    for (index, fld) in enumerate(flds)
        match_val_len = length(match_vals[index])
        value = get_record_value(db, rec_idx, fld)
        value_len = trim_spaces(value.str_val, flds[index].fld_len)
        if equal_str_values(value.str_val, match_vals[index], value_len) == true
           value = u8_array_tostring(value.str_val, value_len)
           str_value = @sprintf "%s" value
            push!(values,str_value)
        else
            return  false,values
        end
    end
    if length(values) == length(flds)
        matched=true
    else matched=false
    end
    return matched,values
end

function select_record(db,flds, match_vals,start_idx,end_idx)
    matches = Any[]
    matched = false
    if start_idx>db.header.no_records
        return matched,matches
    end
    #match_val_len = length(match_vals[1])

    for i = start_idx:end_idx-1
        matched, values = match_record(db,i,flds, match_vals)
        if matched
            push!(matches,values)
            matched=true
        end

        # value = get_record_value(db, i, flds[1])
        # value_len = trim_spaces(value.str_val,flds[1].fld_len)
        # if  match_val_len==value_len && equal_str_values(value.str_val,match_vals[1],value_len)==true
        #     lname_str = u8_array_tostring(value.str_val, value_len)
        #     match = @sprintf "%d: %s" i lname_str
        #     push!(matches, match)
        # end
    end
    return matched,matches
end

function select_records(db, flds, match_vals, no_threads)
    no_recs = db.header.no_records
    record_block_size = trunc(Int32, no_recs / no_threads)
    matches = Any[]
    Threads.@threads for i = 0:no_threads-1
        #for i = 0:no_threads-1
        start_idx = record_block_size * i
        if i == no_threads - 1
            end_idx = start_idx + record_block_size
        else
            end_idx = db.header.no_records
        end
        matched, matches = select_record(
            db,
            flds,
            match_vals,
            start_idx,
            start_idx + record_block_size,
        )
        if matched
            begin
                lock(a)
                try
                    put!(matches)
                finally
                    unlock(a)
                end
            end
        end
        #println(matches)
    end
    return matches

end
function check_end(db,idx)

        if db.data[idx] == 13
            return true
        end
        if idx > db.header.pos_first_record
             return true
        end
        return false
end

# function get_header_field(data,fld_idx)
#     startidx = 33 + fld_idx*32
#     if check_end(data,startidx)==true
#         return nothing,true
#     end
#     fldptr = pointer(data[startidx:startidx+32])
#     fld = unsafe_wrap(DbField, fldptr)
#     return fld, false
# end

function get_string_field(fld)
    s = ""
    for c in fld.fld_name
        nc = @sprintf "%c" c
        if nc == "\0"
            break
        end
        s = string(s, nc)
    end
    return s
end

function get_field_by_name(db, fld_name)
    i=0
    while true
        fld, isend = get_header_field(db,i+=1)
        if isend
            break
        end
        name =  get_string_field(fld)
        if fld_name == name
            return fld,true
        end
    end
    return nothing,false
end


function display_fields(db)
    i=0
    while true
        fld, isend = get_header_field(db,i+=1)
        if isend
            break
        end
        fld_name = get_string_field(fld)
        println(fld_name)
    end
end


function get_field_schema_dic(db)
    dict  = Dict() #Dict{Any,Any}
    i=0
    while true
        fld, isend = get_header_field(db,i+=1)
        if isend
            break
        end
        fld_name = get_string_field(fld)
        fd = FieldDescp(fld.fld_type,fld.fld_offset,fld.fld_len)
        dict[fld_name] = fd
        #println(fld_name)
    end
    return dict
end

file_path = "/Users/rderby/Data/Medical/Data/bu_20201008/Stratford/302926/share/m6nmpt.dbf"

#data = read(file_path)


# data = Vector{UInt8}(undef, sizeof(DbHeader));
# open(file_path) do io
#            readbytes!(io, data)
# end;
# header = unsafe_wrap(DbHeader, pointer(data));
# println(header)

db = load_foxpro(file_path)
# data = open(file_path, "r+") do io
#            Mmap.mmap(io, Vector{UInt8}, file_size) #sizeof(DB_header))
#        end;
# header = unsafe_wrap(DbHeader, pointer(data));
#@printf "position first record %d\n" db.header.pos_first_record
#display_fields(db)

 #matches = Any[]
 #matches = zeros()


#divide records into set of 4
# record_block_size = trunc(Int32,db.header.no_records/4)
# #trunc(Int32, x
# Threads.@threads for i = 0:3
#     start_idx = record_block_size * i
#     matches = select_record(db,"CLNAME","RUBIN",start_idx,start_idx+record_block_size)
#     println(matches)
# end

dict = get_field_schema_dic(db)

flds = FieldDescp[]
push!(flds,dict["CCODE"])
push!(flds,dict["CLNAME"])
push!(flds,dict["CFNAME"])
match_values = String[]
push!(match_values,"*")
push!(match_values,"SMITH")
push!(match_values,"*")

matched_values = select_records(db,flds,match_values,6)
println("matched_values: ", matched_values)

end
