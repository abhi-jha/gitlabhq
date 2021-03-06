<script>
  import { mapActions, mapGetters } from 'vuex';
  import _ from 'underscore';
  import Autosize from 'autosize';
  import { __ } from '~/locale';
  import Flash from '../../flash';
  import Autosave from '../../autosave';
  import TaskList from '../../task_list';
  import * as constants from '../constants';
  import eventHub from '../event_hub';
  import issueWarning from '../../vue_shared/components/issue/issue_warning.vue';
  import markdownField from '../../vue_shared/components/markdown/field.vue';
  import userAvatarLink from '../../vue_shared/components/user_avatar/user_avatar_link.vue';
  import loadingButton from '../../vue_shared/components/loading_button.vue';
  import noteSignedOutWidget from './note_signed_out_widget.vue';
  import discussionLockedWidget from './discussion_locked_widget.vue';
  import issuableStateMixin from '../mixins/issuable_state';

  export default {
    name: 'CommentForm',
    components: {
      issueWarning,
      noteSignedOutWidget,
      discussionLockedWidget,
      markdownField,
      userAvatarLink,
      loadingButton,
    },
    mixins: [
      issuableStateMixin,
    ],
    data() {
      return {
        note: '',
        noteType: constants.COMMENT,
        isSubmitting: false,
        isSubmitButtonDisabled: true,
      };
    },
    computed: {
      ...mapGetters([
        'getCurrentUserLastNote',
        'getUserData',
        'getNoteableData',
        'getNotesData',
        'issueState',
      ]),
      isLoggedIn() {
        return this.getUserData.id;
      },
      commentButtonTitle() {
        return this.noteType === constants.COMMENT ? 'Comment' : 'Start discussion';
      },
      isIssueOpen() {
        return this.issueState === constants.OPENED || this.issueState === constants.REOPENED;
      },
      canCreateNote() {
        return this.getNoteableData.current_user.can_create_note;
      },
      issueActionButtonTitle() {
        if (this.note.length) {
          const actionText = this.isIssueOpen ? 'close' : 'reopen';

          return this.noteType === constants.COMMENT ?
            `Comment & ${actionText} issue` :
            `Start discussion & ${actionText} issue`;
        }

        return this.isIssueOpen ? 'Close issue' : 'Reopen issue';
      },
      actionButtonClassNames() {
        return {
          'btn-reopen': !this.isIssueOpen,
          'btn-close': this.isIssueOpen,
          'js-note-target-close': this.isIssueOpen,
          'js-note-target-reopen': !this.isIssueOpen,
        };
      },
      markdownDocsPath() {
        return this.getNotesData.markdownDocsPath;
      },
      quickActionsDocsPath() {
        return this.getNotesData.quickActionsDocsPath;
      },
      markdownPreviewPath() {
        return this.getNoteableData.preview_note_path;
      },
      author() {
        return this.getUserData;
      },
      canUpdateIssue() {
        return this.getNoteableData.current_user.can_update;
      },
      endpoint() {
        return this.getNoteableData.create_note_path;
      },
    },
    watch: {
      note(newNote) {
        this.setIsSubmitButtonDisabled(newNote, this.isSubmitting);
      },
      isSubmitting(newValue) {
        this.setIsSubmitButtonDisabled(this.note, newValue);
      },
    },
    mounted() {
      // jQuery is needed here because it is a custom event being dispatched with jQuery.
      $(document).on('issuable:change', (e, isClosed) => {
        this.toggleIssueLocalState(isClosed ? constants.CLOSED : constants.REOPENED);
      });

      this.initAutoSave();
      this.initTaskList();
    },
    methods: {
      ...mapActions([
        'saveNote',
        'stopPolling',
        'restartPolling',
        'removePlaceholderNotes',
        'closeIssue',
        'reopenIssue',
        'toggleIssueLocalState',
      ]),
      setIsSubmitButtonDisabled(note, isSubmitting) {
        if (!_.isEmpty(note) && !isSubmitting) {
          this.isSubmitButtonDisabled = false;
        } else {
          this.isSubmitButtonDisabled = true;
        }
      },
      handleSave(withIssueAction) {
        this.isSubmitting = true;

        if (this.note.length) {
          const noteData = {
            endpoint: this.endpoint,
            flashContainer: this.$el,
            data: {
              note: {
                noteable_type: constants.NOTEABLE_TYPE,
                noteable_id: this.getNoteableData.id,
                note: this.note,
              },
            },
          };

          if (this.noteType === constants.DISCUSSION) {
            noteData.data.note.type = constants.DISCUSSION_NOTE;
          }
          this.note = ''; // Empty textarea while being requested. Repopulate in catch
          this.resizeTextarea();
          this.stopPolling();

          this.saveNote(noteData)
            .then((res) => {
              this.isSubmitting = false;
              this.restartPolling();

              if (res.errors) {
                if (res.errors.commands_only) {
                  this.discard();
                } else {
                  Flash(
                    'Something went wrong while adding your comment. Please try again.',
                    'alert',
                    this.$refs.commentForm,
                  );
                }
              } else {
                this.discard();
              }

              if (withIssueAction) {
                this.toggleIssueState();
              }
            })
            .catch(() => {
              this.isSubmitting = false;
              this.discard(false);
              const msg =
                `Your comment could not be submitted!
Please check your network connection and try again.`;
              Flash(msg, 'alert', this.$el);
              this.note = noteData.data.note.note; // Restore textarea content.
              this.removePlaceholderNotes();
            });
        } else {
          this.toggleIssueState();
        }
      },
      enableButton() {
        this.isSubmitting = false;
      },
      toggleIssueState() {
        if (this.isIssueOpen) {
          this.closeIssue()
            .then(() => this.enableButton())
            .catch(() => {
              this.enableButton();
              Flash(__('Something went wrong while closing the issue. Please try again later'));
            });
        } else {
          this.reopenIssue()
            .then(() => this.enableButton())
            .catch(() => {
              this.enableButton();
              Flash(__('Something went wrong while reopening the issue. Please try again later'));
            });
        }
      },
      discard(shouldClear = true) {
        // `blur` is needed to clear slash commands autocomplete cache if event fired.
        // `focus` is needed to remain cursor in the textarea.
        this.$refs.textarea.blur();
        this.$refs.textarea.focus();

        if (shouldClear) {
          this.note = '';
          this.resizeTextarea();
          this.$refs.markdownField.previewMarkdown = false;
        }

        // reset autostave
        this.autosave.reset();
      },
      setNoteType(type) {
        this.noteType = type;
      },
      editCurrentUserLastNote() {
        if (this.note === '') {
          const lastNote = this.getCurrentUserLastNote;

          if (lastNote) {
            eventHub.$emit('enterEditMode', {
              noteId: lastNote.id,
            });
          }
        }
      },
      initAutoSave() {
        if (this.isLoggedIn) {
          this.autosave = new Autosave(
            $(this.$refs.textarea),
            ['Note', 'Issue', this.getNoteableData.id],
            'issue',
          );
        }
      },
      initTaskList() {
        return new TaskList({
          dataType: 'note',
          fieldName: 'note',
          selector: '.notes',
        });
      },
      resizeTextarea() {
        this.$nextTick(() => {
          Autosize.update(this.$refs.textarea);
        });
      },
    },
  };
</script>

<template>
  <div>
    <note-signed-out-widget v-if="!isLoggedIn" />
    <discussion-locked-widget
      issuable-type="issue"
      v-else-if="!canCreateNote"
    />
    <ul
      v-else
      class="notes notes-form timeline">
      <li class="timeline-entry">
        <div class="timeline-entry-inner">
          <div class="flash-container error-alert timeline-content"></div>
          <div class="timeline-icon hidden-xs hidden-sm">
            <user-avatar-link
              v-if="author"
              :link-href="author.path"
              :img-src="author.avatar_url"
              :img-alt="author.name"
              :img-size="40"
            />
          </div>
          <div class="timeline-content timeline-content-form">
            <form
              ref="commentForm"
              class="new-note common-note-form gfm-form js-main-target-form"
            >

              <div class="error-alert"></div>

              <issue-warning
                v-if="hasWarning(getNoteableData)"
                :is-locked="isLocked(getNoteableData)"
                :is-confidential="isConfidential(getNoteableData)"
              />

              <markdown-field
                :markdown-preview-path="markdownPreviewPath"
                :markdown-docs-path="markdownDocsPath"
                :quick-actions-docs-path="quickActionsDocsPath"
                :add-spacing-classes="false"
                ref="markdownField">
                <textarea
                  id="note-body"
                  name="note[note]"
                  class="note-textarea js-vue-comment-form
js-gfm-input js-autosize markdown-area js-vue-textarea"
                  data-supports-quick-actions="true"
                  aria-label="Description"
                  v-model="note"
                  ref="textarea"
                  slot="textarea"
                  :disabled="isSubmitting"
                  placeholder="Write a comment or drag your files here..."
                  @keydown.up="editCurrentUserLastNote()"
                  @keydown.meta.enter="handleSave()"
                  @keydown.ctrl.enter="handleSave()">
                </textarea>
              </markdown-field>
              <div class="note-form-actions">
                <div
                  class="pull-left btn-group
append-right-10 comment-type-dropdown js-comment-type-dropdown droplab-dropdown">
                  <button
                    @click.prevent="handleSave()"
                    :disabled="isSubmitButtonDisabled"
                    class="btn btn-create comment-btn js-comment-button js-comment-submit-button"
                    type="submit">
                    {{ commentButtonTitle }}
                  </button>
                  <button
                    :disabled="isSubmitButtonDisabled"
                    name="button"
                    type="button"
                    class="btn comment-btn note-type-toggle js-note-new-discussion dropdown-toggle"
                    data-toggle="dropdown"
                    aria-label="Open comment type dropdown">
                    <i
                      aria-hidden="true"
                      class="fa fa-caret-down toggle-icon">
                    </i>
                  </button>

                  <ul class="note-type-dropdown dropdown-open-top dropdown-menu">
                    <li :class="{ 'droplab-item-selected': noteType === 'comment' }">
                      <button
                        type="button"
                        class="btn btn-transparent"
                        @click.prevent="setNoteType('comment')">
                        <i
                          aria-hidden="true"
                          class="fa fa-check icon">
                        </i>
                        <div class="description">
                          <strong>Comment</strong>
                          <p>
                            Add a general comment to this issue.
                          </p>
                        </div>
                      </button>
                    </li>
                    <li class="divider droplab-item-ignore"></li>
                    <li :class="{ 'droplab-item-selected': noteType === 'discussion' }">
                      <button
                        type="button"
                        class="btn btn-transparent"
                        @click.prevent="setNoteType('discussion')">
                        <i
                          aria-hidden="true"
                          class="fa fa-check icon">
                        </i>
                        <div class="description">
                          <strong>Start discussion</strong>
                          <p>
                            Discuss a specific suggestion or question.
                          </p>
                        </div>
                      </button>
                    </li>
                  </ul>
                </div>

                <loading-button
                  v-if="canUpdateIssue"
                  :loading="isSubmitting"
                  @click="handleSave(true)"
                  :container-class="[
                    actionButtonClassNames,
                    'btn btn-comment btn-comment-and-close js-action-button'
                  ]"
                  :disabled="isSubmitting"
                  :label="issueActionButtonTitle"
                />

                <button
                  type="button"
                  v-if="note.length"
                  @click="discard"
                  class="btn btn-cancel js-note-discard">
                  Discard draft
                </button>
              </div>
            </form>
          </div>
        </div>
      </li>
    </ul>
  </div>
</template>
