CLASS zcl_ags_service_rest DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.

    INTERFACES zif_ags_service.

    METHODS constructor
      IMPORTING
        !ii_server TYPE REF TO if_http_server.
  PROTECTED SECTION.
  PRIVATE SECTION.

    TYPES:
      BEGIN OF ty_file,
        filename TYPE string,
        sha1     TYPE zags_sha1,
      END OF ty_file.
    TYPES:
      ty_files_tt TYPE STANDARD TABLE OF ty_file WITH DEFAULT KEY.

    DATA mi_server TYPE REF TO if_http_server.

    METHODS list_repos
      RETURNING
        VALUE(rt_list) TYPE zcl_ags_repo=>ty_repos_tt
      RAISING
        zcx_ags_error.
    METHODS read_blob
      IMPORTING
        !iv_repo           TYPE zags_repo_name
        !iv_branch         TYPE string
        !iv_filename       TYPE string
      RETURNING
        VALUE(rv_contents) TYPE xstring
      RAISING
        zcx_ags_error.
    METHODS list_files
      IMPORTING
        !iv_name        TYPE zags_repo_name
      RETURNING
        VALUE(rt_files) TYPE ty_files_tt
      RAISING
        zcx_ags_error.
    METHODS to_json
      IMPORTING
        !ig_data       TYPE any
      RETURNING
        VALUE(rv_json) TYPE xstring.
ENDCLASS.



CLASS ZCL_AGS_SERVICE_REST IMPLEMENTATION.


  METHOD constructor.

    mi_server = ii_server.

  ENDMETHOD.


  METHOD list_files.
* todo, unit test this method
* todo, move this method to somewhere else?
* todo, read specific branch
    TYPES: BEGIN OF ty_tree,
             sha1 TYPE zags_sha1,
             base TYPE string,
           END OF ty_tree.

    DATA: lt_trees TYPE STANDARD TABLE OF ty_tree WITH DEFAULT KEY.

    DATA(lo_repo) = NEW zcl_ags_repo( iv_name ).
    DATA(lo_branch) = lo_repo->get_branch( lo_repo->get_data( )-head ).
    DATA(lo_commit) = NEW zcl_ags_obj_commit( lo_branch->get_data( )-sha1 ).
    APPEND VALUE #( sha1 = lo_commit->get_tree( ) base = '/' ) TO lt_trees.

    LOOP AT lt_trees ASSIGNING FIELD-SYMBOL(<ls_tree>).
      DATA(lo_tree) = NEW zcl_ags_obj_tree( <ls_tree>-sha1 ).
      LOOP AT lo_tree->get_files( ) ASSIGNING FIELD-SYMBOL(<ls_file>).
        CASE <ls_file>-chmod.
          WHEN zcl_ags_obj_tree=>c_chmod-dir.
            APPEND VALUE #(
              sha1 = lo_commit->get_tree( )
              base = <ls_tree>-base && <ls_file>-name && '/' )
              TO lt_trees.
          WHEN OTHERS.
            APPEND VALUE #(
              filename = <ls_tree>-base && <ls_file>-name
              sha1 = <ls_file>-sha1 ) TO rt_files.
        ENDCASE.
      ENDLOOP.
    ENDLOOP.

  ENDMETHOD.


  METHOD list_repos.

    rt_list = zcl_ags_repo=>list( ).

  ENDMETHOD.


  METHOD read_blob.

    DATA(lt_files) = list_files( iv_repo ).

    READ TABLE lt_files ASSIGNING FIELD-SYMBOL(<ls_file>) WITH KEY filename = iv_filename.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_ags_error
        EXPORTING
          textid = zcx_ags_error=>m011.
    ENDIF.

    DATA(lo_blob) = NEW zcl_ags_obj_blob( <ls_file>-sha1 ).
    rv_contents = lo_blob->get_data( ).

  ENDMETHOD.


  METHOD to_json.

    DATA: lo_writer TYPE REF TO cl_sxml_string_writer.

    lo_writer = cl_sxml_string_writer=>create( if_sxml=>co_xt_json ).
    CALL TRANSFORMATION id
      SOURCE data = ig_data
      RESULT XML lo_writer.
    rv_json = lo_writer->get_output( ).

  ENDMETHOD.


  METHOD zif_ags_service~run.

    DATA: lv_path     TYPE string,
          lv_last     TYPE string,
          lv_filename TYPE string,
          lv_branch   TYPE string,
          lv_name     TYPE zags_repo_name.


    lv_path = mi_server->request->get_header_field( '~path' ).

*****************************
* /list/
*
* /repo/(repo)/blob/(commit/branch)/(filename)
* /repo/(repo)/tree/(branch/sha1)
* /repo/(repo)/commits/(branch)
* /repo/(repo)/commit/(sha1)
*****************************

    DATA(lv_base) = '/sap/zgit/rest'.

    FIND REGEX lv_base && '/repo/(\w*)/'
      IN lv_path
      SUBMATCHES lv_name ##NO_TEXT.

    FIND REGEX lv_base && '/(\w*)$'
      IN lv_path
      SUBMATCHES lv_last ##NO_TEXT.

    IF lv_path CP lv_base && '/list/'.
      mi_server->response->set_data( to_json( list_repos( ) ) ).
    ELSEIF lv_path CP lv_base && '/repo/*/tree/*'.
      mi_server->response->set_data( to_json( list_files( lv_name ) ) ).
    ELSEIF lv_path CP lv_base && '/repo/*/blob/*'.
      FIND REGEX '/blob/(\w+)(/.*)$'
        IN lv_path
        SUBMATCHES lv_branch lv_filename ##NO_TEXT.
      mi_server->response->set_data( read_blob(
        iv_repo     = lv_name
        iv_branch   = lv_branch
        iv_filename = lv_filename ) ).
    ELSEIF lv_path CP lv_base && '/repo/*/commit/*'.
* todo
    ELSEIF lv_path CP lv_base && '/repo/*/commits/*'.
* todo
    ELSE.
      RAISE EXCEPTION TYPE zcx_ags_error
        EXPORTING
          textid = zcx_ags_error=>m010.
    ENDIF.

  ENDMETHOD.
ENDCLASS.